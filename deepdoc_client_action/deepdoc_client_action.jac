import:py os;
import:py requests;
import:py logging;
import:py traceback;
import:py from logging { Logger }
import:jac from jivas.agent.action.action { Action }
import:py from jvserve.lib.agent_interface { AgentInterface }
import:py from jvserve.lib.file_interface { file_interface }
import:jac from jivas.agent.memory.collection { Collection }
import:jac from actions.jivas.deepdoc_client_action.job_entry { JobEntry }
import:jac from actions.jivas.deepdoc_client_action.doc_entry { DocEntry }
import:jac from actions.jivas.deepdoc_client_action.doc_file_entry { DocFileEntry }
import:jac from actions.jivas.deepdoc_client_action.doc_url_entry { DocURLEntry }
import:jac from actions.jivas.deepdoc_client_action.item_status { ItemStatus }


node DeepDocClientAction :Action: {
    # Integrates with DeepDoc OCR and document parsing services to ingest documents into a vector store

    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    # api url to deepdoc service
    has api_url:str = os.environ.get('DEEPDOC_API_URL', '');
    has api_key:str = os.environ.get('DEEPDOC_API_KEY','api-key');
    has base_url:str = os.environ.get('JIVAS_BASE_URL', '');
    has vector_store_action:str = "TypesenseVectorStoreAction";
    has doc_manifest:dict = {}; # maintained for migrations

    can on_register() -> None {
        # """
        # Registers the DeepDocClientAction with the agent's action collection.
        # executes any migration on older deepdoc manifest entries.
        # """

        # Check if the doc_manifest dictionary is not empty, indicating a migration is needed
        self.migrate_manifest();
    }

    can healthcheck() {
        # """
        # Checks the health of the DeepDoc service by sending a GET request to the health endpoint.

        # Returns:
        #     bool: True if the service is healthy, False otherwise.
        # """
        if self.base_url == "" {
            return {
                "status": False,
                "message": "Base URL is not set.",
                "severity": "error"
            };
        }
        if self.api_url == "" {
            return {
                "status": False,
                "message": "API URL is not set.",
                "severity": "error"
            };
        }
        try {
            response = requests.get(f"{self.api_url}/health");
            return response.status_code == 200;
        } except Exception as e {
            self.logger.error(traceback.format_exc());
            return {
                "status": False,
                "message": f"DeepDoc service is not reachable: {str(e)}",
                "severity": "error"
            };
        }
    }

    can queue_job(
        urls:list[str]=[],
        files:list[dict]=[],
        metadatas:list[dict]=[],
        from_page:int=0,
        to_page:int=100000,
        lang:str="english",
        callback_url:str=""
    ) -> str {

        # """
        # Sends a request to the DeepDoc service to queue documents for processing.

        # Args:
        #     urls (list[str]): List of document URLs to process.
        #     files (list[bytes]): List of file contents to process.
        #     metadatas (list[dict]): List of metadata dictionaries for each file.
        #     from_page (int): Starting page number for processing.
        #     to_page (int): Ending page number for processing.
        #     lang (str): Language of the documents.
        #     callback_url (str): Optional callback URL for job completion notification.

        # Returns:
        #     str: The job ID returned by the DeepDoc service.
        # """
        if self.healthcheck() != True {
            self.logger.error("Healthcheck for DeepDoc Client failed. Check your configuration.");
            return "";
        }

        try {

            # Prepare the payload for the request
            payload = {
                "from_page": from_page,
                "to_page": to_page,
                "lang": lang
            };

            # Include the callback URL if provided
            if callback_url {
                payload["callback_url"] = callback_url;
            }

            if urls {
                # Add URLs to the payload if provided
                payload["urls"] = urls;
            }

            # Prepare the files for the request
            files_data = [];
            for file in files {

                if "name" in file and "type" in file and "content" in file {

                    if file["name"] in [f[1][0] for f in files_data] {
                        # ensure we do not have multiple instances of the same file in file_data
                        self.logger.error(f"File {file['name']} already exists in the request. Skipping duplicate.");

                    } else {
                        # Add the file to the files_data list
                        files_data.append(
                            (
                                "files",
                                (
                                    file["name"],
                                    file["content"],
                                    file["type"]
                                )
                            )
                        );
                    }

                } else {
                    self.logger.error(f"Invalid file format: {file}");
                    return "";
                }
            }

            if not files_data and not urls {
                self.logger.error("No valid files provided for processing.");
                return "";
            }

            # Make the POST request to the DeepDoc service
            response = requests.post(
                f"{self.api_url}/upload_and_chunk",
                files=files_data,
                data=payload
            );

            if not response {
                self.logger.error("No response from DeepDoc service.");
                return "";
            }

            # Check if the response is successful
            if response.status_code != 200 {
                self.logger.error(f"Failed to queue documents: {response.text}");
                return "";
            }

            # Parse the response JSON
            response_data = response.json();
            if "job_id" in response_data {

                job_id = response_data["job_id"];

                # create or retrieve the job entry node
                job_entry = self.get_job_entry(job_id=job_id);

                if(not job_entry) {
                    # grab action collection
                    collection = self.get_collection();
                    # create a new job entry node
                    job_entry = JobEntry(job_id = job_id);
                     # attach the job_entry node to collection
                    collection ++> job_entry;
                }

                # set the job entry status to processing
                job_entry.set_status(ItemStatus.PROCESSING);

                if(files_data) {

                    # if files are in play, we archive the uploaded file(s) as under job_id in the doc_manifest
                    for (index, file_tuple) in enumerate(files_data) {
                        name = file_tuple[1][0];
                        file_content = file_tuple[1][1];
                        mimetype = file_tuple[1][2];
                        metadata = metadatas[index] if metadatas and index < len(metadatas) else {};

                        # ensure the output filename is without whitespaces and slashes
                        output_filename = f"{job_id}_{self.format_filename(name)}";
                        # save document to the file system
                        self.save_file(output_filename, file_content);
                        # retrieve short file url
                        source = self.get_short_file_url(f"{output_filename}");
                        # update metadata
                        metadata["source"] = source;
                        metadata["filename"] = name;
                        metadata["job_id"] = job_id;
                        job_entry.add_doc_file_entry(
                          name = name,
                          source = source,
                          mimetype = mimetype,
                          metadata = metadata
                        );
                    }
                }

                if urls {
                    # if urls are in play, we archive the uploaded file(s) as under job_id in the doc_manifest
                    for (index, url) in enumerate(urls) {
                        metadata = metadatas[index] if metadatas and index < len(metadatas) else {};
                        # update metadata
                        metadata["source"] = url;
                        metadata["filename"] = url.split("/")[-1];
                        metadata["job_id"] = job_id;
                        job_entry.add_doc_url_entry(
                            url = url,
                            metadata = metadata
                        );
                    }
                }

                return response_data["job_id"];
            } else {
                self.logger.error("Response does not contain job_id.");
                return "";
            }
        } except Exception as e {
            self.logger.error(f"Exception occurred while queuing documents: {str(e)}");
            self.logger.error(traceback.format_exc());
            return "";
        }
    }

    can get_job_status(job_id:str) -> dict {
        # """
        # Retrieves the status of a queued job from the DeepDoc service.

        # Args:
        #     job_id (str): The ID of the job to check.

        # Returns:
        #     dict: The status and result of the job.
        # """
        try {
            # Make the GET request to the DeepDoc service
            response = requests.get(f"{self.api_url}/job/{job_id}");

            # Check if the response is successful
            if response.status_code != 200 {
                self.logger.error(f"Failed to get job status: {response.text}");
                return {"status": "error", "error": response.text};
            }

            # Parse the response JSON
            response_data = response.json();

            # Ensure the response contains the expected fields
            if "status" in response_data {
                return response_data;
            } else {
                self.logger.error("Response does not contain 'status' field.");
                return {"status": "error", "error": "Invalid response format"};
            }
        } except Exception as e {
            self.logger.error(f"Exception occurred while getting job status: {str(e)}");
            self.logger.error(traceback.format_exc());
            return {"status": "error", "error": str(e)};
        }
    }

    can cancel_job(job_id:str) -> dict {
        # """
        # Cancels a deepdoc job which is still in processing

        # Args:
        #     job_id (str): The ID of the job to cancel.

        # Returns:
        #     dict: The status and result of the job.
        # """
        try {
            # Make the GET request to the DeepDoc service
            response = requests.post(f"{self.api_url}/job/{job_id}/cancel");

            # Check if the response is successful
            if response.status_code != 200 {
                self.logger.error(f"Failed to cancel job: {response.text}");
                return {"status": "error", "error": response.text};
            }

            # now remove the job entry from the collection
            job_entry = self.get_job_entry(job_id=job_id);
            if job_entry {
                # set the job entry status to cancelled
                job_entry.set_status(ItemStatus.CANCELLED);

                # now remove any document entries associated with the job
                doc_entries = job_entry.get_doc_entries();
                if doc_entries {
                    for doc_entry in doc_entries {
                        # set the doc entry status to cancelled
                        doc_entry.set_status(ItemStatus.CANCELLED);
                    }
                }

            } else {
                self.logger.error(f"Job entry with ID {job_id} not found in the collection.");
            }

            # Parse the response JSON
            response_data = response.json();

        } except Exception as e {
            self.logger.error(f"Exception occurred while attempting to cancel the job: {str(e)}");
            self.logger.error(traceback.format_exc());
            return {"status": "error", "error": str(e)};
        }
    }

    can ingest_job(job_id:str, job_data:dict) -> bool {
        # """
        # Imports the results of a completed job into the vector store using add_texts.

        # Args:
        #     job_data (dict): The data returned from the DeepDoc service for the completed job.

        # Returns:
        #     bool: True if the import was successful, False otherwise.
        # """

        # Ensure the job status is completed
        if job_data.get("status") == "error" {
            self.logger.error(f"Unable to ingest failed job data");
            job_entry = self.get_job_entry(job_id=job_id);
            job_entry.set_status(ItemStatus.FAILED);
            return False;
        }

        if job_data.get("status") != "completed" {
            self.logger.error("Unable to ingest incomplete job data.");
            return False;
        }

        # Extract the result field from the job data
        results = job_data.get("result", []);
        if not results {
            self.logger.error("No results found in job data.");
            job_entry = self.get_job_entry(job_id=job_id);
            job_entry.set_status(ItemStatus.FAILED);
            return False;
        }

        # Get the vector store action and ingest the texts
        vector_store_action = self.get_agent().get_action(action_label=self.vector_store_action);
        if not vector_store_action {
            self.logger.error(f"Vector store action '{self.vector_store_action}' not found.");
            job_entry = self.get_job_entry(job_id=job_id);
            job_entry.set_status(ItemStatus.FAILED);
            return False;
        }

        doc_entry = None;
        # grab the job in question
        job_entry = self.get_job_entry(job_id=job_id);

        if not job_entry {
            self.logger.error(f"Job entry '{job_id}' not found.");
            return False;
        }

        try {
            # set job_entry status to ingesting
            job_entry.set_status(ItemStatus.INGESTING);
            # for storing processed raw page ranges to determine first and last page at the end
            page_ranges = [];
            # Prepare texts and metadatas and ingest
            for result in results {

                text = result.get("text", "");
                metadata = result.get("metadata", {});

                if(text == "") {
                    self.logger.error(f"Empty text in result: {result}");
                    continue;
                }

                # Consolidate page numbers into a range string (e.g., "1-2")
                page_numbers = metadata.get("page_num_int", []);
                page_ranges.extend(page_numbers);
                page_range = self.format_page_range(page_numbers);

                filtered_metadata = {
                    "page": page_range,
                    "filename": metadata.get("original_filename", ""),
                    "job_id": job_id
                };

                # if there's a previous doc entry that completed, set the status to completed
                if doc_entry {
                    # set the previous doc entry status to completed
                    doc_entry.set_status(ItemStatus.COMPLETED);
                }

                # add any custom metadata to the filtered_metadata dict
                doc_entry = job_entry.get_doc_entry_by_name(filtered_metadata["filename"]);

                if not doc_entry {
                    self.logger.error(f"No document entry found for filename: {filtered_metadata['filename']}");
                    continue;  # skip if no doc entry found for this filename
                }
                # update the manifest entry with the consolidated metadata
                doc_entry.add_metadata("filename", filtered_metadata["filename"]);
                # set doc entry status to ingesting
                doc_entry.set_status(ItemStatus.INGESTING);
                # filter out metadata keys that are not in the filtered_metadata
                filtered_metadata.update(doc_entry.get_metadata());
                # set the current page range in metadata, it was reset by update above
                filtered_metadata["page"] = page_range;
                # add the source to the filtered metadata
                filtered_metadata["source"] = doc_entry.get_source();

                ids = vector_store_action.add_texts(
                    texts=[text],
                    metadatas=[filtered_metadata],
                    ids=[result.get("id") or f"doc_{os.urandom(8).hex()}"]
                );

                if(ids) {
                    chunk_id = ids[0];
                    # update the manifest with the chunk ID for this document
                    doc_entry.add_chunk_id(chunk_id);
                    # log the chunk ID and metadata
                    self.logger.info(f"{chunk_id} added to vector store with metadata: {filtered_metadata}");
                }
            }
            if doc_entry {
                # set the last doc entry status to completed
                doc_entry.set_status(ItemStatus.COMPLETED);
                # update the metadata with the page range for the document
                if page_ranges {
                    # format the page range and update the doc entry metadata
                    document_page_range = self.format_page_range(page_ranges);
                    doc_entry.add_metadata("page", document_page_range);
                }
            }
            # set job_entry status to completed
            job_entry.set_status(ItemStatus.COMPLETED);

            return True;

        } except Exception as e {
            self.logger.error(f"Exception occurred while importing job data: {str(e)}");
            self.logger.error(traceback.format_exc());
            # set job_entry status to failed
            job_entry.set_status(ItemStatus.FAILED);
            # set the current doc_entry status to failed if it exists
            if doc_entry {
                doc_entry.set_status(ItemStatus.FAILED);
            }
            return False;
        }
    }

    can format_page_range(page_list:list[int]) -> str {
        # takes a list of page numbers for chunks and returns a string representing the range

        if not page_list {
            return "1";
        }

        # Remove duplicates and sort
        unique_pages = sorted(list(set(page_list)));

        if len(unique_pages) == 1 {
            return str(unique_pages[0]);
        }

        # Group consecutive pages
        ranges = [];
        start = unique_pages[0];
        prev = start;

        for num in unique_pages[1:] {
            if num == prev + 1 {
                prev = num;
            } else {
                ranges.append([start, prev]);
                start = num;
                prev = num;
            }
        }
        ranges.append([start, prev]);

        # Format the ranges
        range_strings = [];
        for r in ranges {
            if r[0] == r[1] {
                range_strings.append(str(r[0]));
            } else {
                range_strings.append(f"{r[0]}-{r[1]}");
            }
        }

        return ", ".join(range_strings);
    }

    can generate_callback_url(walker_name:str) -> str {
        # setup procedure for webhook registration on deepdoc

        base_url = self.base_url;
        callback_url = "";

        agent_id = self.get_agent().id;
        module_root = self.get_module_root();
        # generate webhook key
        webhook_key = AgentInterface.encrypt_webhook_key(agent_id=agent_id, module_root=module_root, walker=walker_name);

        if(base_url and webhook_key) {
            # complete the full webhook url
            callback_url = f'{base_url}/webhook/{webhook_key}';
        } else {
            self.logger.error('unable to generate webhook url for DeepDoc Client, missing required parameters');
            return "";
        }

        return callback_url;
    }

    can get_job_entry(job_id:str) -> JobEntry {
        collection = self.get_collection();
        return (collection spawn _get_job_entry(job_id=job_id)).job_entry;
    }

    can list_doc_entries(page:int, limit:int) -> list[dict] {
        # Lists all document entries in the manifest with pagination.

        collection = self.get_collection();
        result = collection spawn _list_doc_entries(page=page, limit=limit);
        if not result {
            self.logger.error("No document entries found in the manifest.");
            return {};
        }
        return {
            "page": result.page,
            "limit": result.limit,
            "total_items": result.total_items,
            "total_pages": result.total_pages,
            "has_previous": result.has_previous,
            "has_next": result.has_next,
            "items": result.items
        };
    }

    can get_doc_entry(job_id:str, doc_id:str) -> dict {
        # Returns the document manifest entry by id.

        job_entry = self.get_job_entry(job_id=job_id);

        if not job_entry {
            self.logger.error(f"Job ID {job_id} not found in doc manifest.");
            return {};
        }

        doc_entry = job_entry.get_doc_entry(id=doc_id);

        if not doc_entry {
            self.logger.error(f"Document entry with ID '{doc_id}' not found.");
            return {};
        }

        return doc_entry.export();
    }

    can delete_doc_entry(job_id:str, doc_id:str) -> bool {
        # Deletes a specific entry from the document manifest for a given job ID.
        # set manifesrt_only to True to delete the entry from the manifest only and not the file system

        job_entry = self.get_job_entry(job_id=job_id);

        if not job_entry {
            self.logger.error(f"Job ID {job_id} not found in doc manifest.");
            return False;
        }

        doc_entry = job_entry.get_doc_entry(id=doc_id);

        if not doc_entry {
            self.logger.error(f"Document entry with ID '{doc_id}' not found.");
            return False;
        }

        if not isinstance(doc_entry, DocURLEntry) {
            # Attempt to delete the file from the filesystem if not url
            try {
                self.delete_file(f"{job_id}_{self.format_filename(doc_entry.name)}");
            } except Exception as e {
                self.logger.error(f"Failed to delete file from filesystem: {str(e)}");
            }
        }

        # remove any vector strore entries associated with the file
        self.remove_doc_vector_store_entries(job_id=job_id, doc_id=doc_id);
        # finally remove the doc entry from the job.. and the entire job if it's the last entry
        job_entry.delete_doc_entry(doc_id);

        return True;
    }

    can delete_job_entry(job_id:str) -> bool {
        # Deletes all entries for a specific job ID from the document manifest and everywhere else.

        job_entry = self.get_job_entry(job_id=job_id);

        if not job_entry {
            self.logger.error(f"Job ID {job_id} not found in doc manifest.");
            return False;
        }

        # iterate through and delete all document entries associated with the job ID
        doc_entries = job_entry.get_doc_entries();

        if not doc_entries {
            self.logger.info(f"No document entries found for job ID {job_id}. Removing job entry only.");
            # If no document entries, just remove the job entry
            job_entry.delete();
            return True;  # Nothing to remove, so return success
        }
        for doc_entry in doc_entries {
            # remove the document entry
            self.delete_doc_entry(job_id=job_id, doc_id=doc_entry.id);
        }

        return True;  # Successfully removed all document entries for the job ID
    }

    can remove_doc_vector_store_entries(job_id:str, doc_id:str) -> bool {
        # Removes all vector store entries associated with a specific document by ID.
        job_entry = self.get_job_entry(job_id=job_id);

        if not job_entry {
            self.logger.error(f"Job ID {job_id} not found in doc manifest.");
            return False;
        }

        # Retrieve the vector store action
        vector_store_action = self.get_agent().get_action(action_label=self.vector_store_action);
        if not vector_store_action {
            self.logger.error(f"Vector store action '{self.vector_store_action}' not found.");
            return False;
        }

        # Retrieve the document manifest entry for the specified job ID and filename
        item = job_entry.get_doc_entry(id=doc_id);
        if not item {
            self.logger.error(f"Document manifest entry for job ID '{job_id}' and filename '{item.name}' not found.");
            return False;
        }

        # Extract chunk IDs from the document manifest entry
        chunk_ids = item.get_chunk_ids();
        if not chunk_ids {
            self.logger.info(f"No chunk IDs found for job ID '{job_id}' and filename '{item.name}'.");
            return True;  # Nothing to remove, so return success
        }

        # Attempt to delete each chunk ID from the vector store
        success = True;
        for chunk_id in chunk_ids {
            if not vector_store_action.delete_document(id=chunk_id) {
                self.logger.error(f"Failed to delete vector store entry with chunk ID '{chunk_id}' for filename '{item.name}'.");
                success = False;
            }
        }

        if success {
            self.logger.info(f"Successfully removed all vector store entries for job ID '{job_id}' and filename '{item.name}'.");
        }

        return success;
    }

    can format_filename(filename:str) -> str {
        # Formats the filename by removing spaces and slashes.
        # Returns the formatted filename.

        if not filename {
            self.logger.error("Filename is empty or None.");
            return filename;
        }

        # Remove spaces and slashes from the filename
        formatted_filename = filename.replace(" ", "_").replace("/", "_").replace("\\", "_");

        return formatted_filename;
    }

    can migrate_manifest() -> None {
        # """
        # Migrates the old manifest entries to the new format.
        # This is a placeholder for future migration logic.
        # """
        if self.doc_manifest {

            self.logger.info("Migrating old DeepDoc manifest entries to new format.");

            collection = self.get_collection();
            vector_store_action = self.get_agent().get_action(action_label=self.vector_store_action);
            jobs_to_remove = [];

            if not vector_store_action {
                self.logger.error(f"Vector store action '{self.vector_store_action}' not found. Unable to continue migration.");
                return False;
            }

            # Iterate over each job_id and its associated entries in the old manifest
            for (job_id, entries) in self.doc_manifest.items() {

                job_entry = JobEntry(job_id=job_id);

                collection ++> job_entry;
                all_entries_processed = True;

                # Iterate over each entry (document/file/url) in the job
                for entry in entries {
                    # Check if the entry has the required fields
                    if "file_path" in entry and "filename" in entry and "file_type" in entry {
                        # If the entry is a URL type
                        if entry["file_type"] == "url" {
                            # Create a DocURLEntry node for the URL
                            doc_url_entry = DocURLEntry(
                            job_id=job_id,
                            name=entry["filename"],
                            source=entry["file_path"],
                            metadata=entry.get("metadata", {}),
                            chunk_ids=entry.get("chunk_ids", [])
                            );
                            doc_url_entry.set_status(ItemStatus.COMPLETED);
                            # Attach the DocURLEntry node to the job_entry
                            job_entry ++> doc_url_entry;
                            self.logger.info(f"URL {entry['filename']} successfully migrated.");
                        } else {
                            # Otherwise, treat as a file (not a URL)
                            try {
                                # If the file_path is a remote URL, download it
                                if entry["file_path"].startswith("http://") or entry["file_path"].startswith("https://") {

                                    output_filename = f"{job_id}_{self.format_filename(entry['filename'])}";

                                    # get the old file content
                                    output_file_path = f"ddc/{output_filename}";
                                    file_contents = file_interface.get_file(output_file_path);

                                    # If retrieval is successful
                                    if file_contents {
                                        # Save the file to local storage
                                        self.save_file(output_filename, file_contents);
                                        # Get the local file URL/path
                                        updated_source = self.get_short_file_url(output_filename);
                                        metadata = entry.get("metadata", {});
                                        chunk_ids = entry.get("chunk_ids", []);
                                        # update source in metadata if it exists
                                        if "source" in metadata {
                                            metadata["source"] = updated_source;
                                        }
                                        # Create a DocFileEntry node for the file
                                        doc_file_entry = DocFileEntry(
                                            job_id=job_id,
                                            name=entry["filename"],
                                            source=updated_source,
                                            mimetype=entry["file_type"],
                                            metadata=metadata,
                                            chunk_ids=chunk_ids
                                        );

                                        # Attach the DocFileEntry node to the job_entry
                                        job_entry ++> doc_file_entry;

                                        # update the vector store metadata with the new source
                                        for chunk_id in chunk_ids {
                                            # update the vector store entry with the new source
                                            vector_store_action.update_document(
                                                id=chunk_id,
                                                data={'metadata': metadata}
                                            );
                                            self.logger.info(f"Metadata for {chunk_id} successfully updated.");
                                        }
                                        doc_file_entry.set_status(ItemStatus.COMPLETED);
                                        self.logger.info(f"File {entry['filename']} successfully migrated.");

                                        # delete the old file entry from the manifest, with recreated old filename
                                        file_interface.delete_file(output_file_path);
                                    } else {
                                        # Log an error if the file could not be downloaded
                                        self.logger.error(f"Failed to download file from {entry['file_path']}: {response.status_code}");
                                        all_entries_processed = False;
                                    }
                                }
                            } except Exception as e {
                                # Log any exceptions that occur during file download or processing
                                self.logger.error(f"Error copying file from {entry['file_path']}: {str(e)}");
                                self.logger.error(traceback.format_exc());
                                all_entries_processed = False;
                            }
                        }
                    } else {
                        # Log an error if the entry format is invalid
                        self.logger.error(f"Invalid entry format: {entry}");
                        all_entries_processed = False;
                    }
                }
                # If all entries for this job were processed, mark the job for removal from the old manifest
                if all_entries_processed {
                    jobs_to_remove.append(job_id);
                    job_entry.set_status(ItemStatus.COMPLETED);
                }

            }
            # Remove all jobs that were successfully migrated from the old doc_manifest
            for job_id in jobs_to_remove {
                del self.doc_manifest[job_id];
            }
        }
    }

}

walker _get_job_entry {
    # spawns on action collection and finds a job by job_id

    has job_id:str = "";
    has job_entry:JobEntry = None;

    obj __specs__ {
        # make this a private walker
        static has private: bool = True;
    }

    can on_collection with Collection entry {
        visit [-->](`?JobEntry)(?job_id == self.job_id);
    }

    can on_job_entry with JobEntry entry {
        self.job_entry = here;
    }

}

walker _list_doc_entries {
    # Spawns on action collection and returns a paginated, flattened list of doc entries with total count and page control

    has page:int = 1;               # page number, 1-based
    has limit:int = 50;             # number of items per page, 0 means all
    has offset:int = 0;             # calculated from page and limit
    has total_items:int = 0;        # total number of items
    has total_pages:int = 1;
    has has_previous:bool = False;
    has has_next:bool = False;
    has current_index:int = 0;
    has items:list = [];

    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    obj __specs__ {
        static has private: bool = True;
    }

    can on_collection with Collection entry {
        # First, count total doc entries
        self.total_items = 0;
        job_entries = [-->](`?JobEntry);

        for job in job_entries {
            self.total_items += len(job.get_doc_entries());
        }

        # Calculate offset based on page and limit
        if self.limit > 0 {
            self.offset = (self.page - 1) * self.limit;
            self.total_pages = (self.total_items // self.limit) + (1 if self.total_items % self.limit > 0 else 0);
            self.has_previous = self.page > 1;
            self.has_next = self.page < self.total_pages;
        } else {
            self.offset = 0;
            self.total_pages = 1;
            self.has_previous = False;
            self.has_next = False;
        }

        visit [-->](`?JobEntry);
    }

    can on_job_entry with JobEntry entry {
        visit [-->](`?DocEntry);
    }

    can on_doc_entry with DocEntry entry {
        if self.current_index >= self.offset and (self.limit == 0 or len(self.items) < self.limit) {
            self.items.append(here.export());
        }
        self.current_index += 1;
        if self.limit != 0 and len(self.items) >= self.limit {
            disengage;
        }
    }
}