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
    has api_url:str = os.environ.get('DEEPDOC_API_URL', 'https://deepdoc.trueselph.com');
    has api_key:str = os.environ.get('DEEPDOC_API_KEY','api-key');
    has base_url:str = os.environ.get('JIVAS_BASE_URL', '');
    has vector_store_action:str = "TypesenseVectorStoreAction";
    has doc_manifest:dict = {}; # maintained for migrations
    has cancelled_jobs:list = [];

    can healthcheck() {
        # """
        # Checks the health of the DeepDoc service by sending a GET request to the health endpoint.

        # Returns:
        #     bool: True if the service is healthy, False otherwise.
        # """
        if self.base_url == "" {
            self.logger.error("Healthcheck for DeepDoc Client failed. Base URL is not set.");
            return False;
        }
        try {
            response = requests.get(f"{self.api_url}/health");
            return response.status_code == 200;
        } except Exception as e {
            self.logger.error(f"Healthcheck for DeepDoc Client failed. DeepDoc service is not reachable: {str(e)}");
            self.logger.error(traceback.format_exc());
            return False;
        }
    }

    can queue_deepdoc_job(
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
                # grab action collection
                collection = self.get_collection();
                # create the job entry node
                job_entry = JobEntry(
                    job_id = job_id,
                    status = ItemStatus.PROCESSING
                );
                # attach the job_entry node to collection
                collection ++> job_entry;

                if(files_data) {

                    # if files are in play, we archive the uploaded file(s) as under job_id in the doc_manifest
                    for (index, file_tuple) in enumerate(files_data) {
                        name = file_tuple[1][0];
                        file_content = file_tuple[1][1];
                        mimetype = file_tuple[1][2];
                        metadata = metadatas[index] if metadatas and index < len(metadatas) else {};

                        # ensure the output filename is without whitespaces and slashes
                        output_filename = f"{job_id}_{self.format_filename(name)}";
                        output_file_path = f"ddc/{output_filename}";
                        # save document to the file system
                        self.get_agent().save_file(output_file_path, file_content);
                        # retrieve file url
                        source = self.get_agent().get_file_url(f"ddc/{output_filename}");

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

    can get_deepdoc_job_status(job_id:str) -> dict {
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

    can ingest_deepdoc_job(job_id:str, job_data:dict) -> bool {
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
            job_entry = self.get_job(job_id=job_id);
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
            job_entry = self.get_job(job_id=job_id);
            job_entry.set_status(ItemStatus.FAILED);
            return False;
        }

        # Get the vector store action and ingest the texts
        vector_store_action = self.get_agent().get_actions().get(action_label=self.vector_store_action);
        if not vector_store_action {
            self.logger.error(f"Vector store action '{self.vector_store_action}' not found.");
            job_entry = self.get_job(job_id=job_id);
            job_entry.set_status(ItemStatus.FAILED);
            return False;
        }

        doc_entry = None;
        # grab the job in question
        job_entry = self.get_job(job_id=job_id);

        if not job_entry {
            self.logger.error(f"Job entry '{job_id}' not found.");
            return False;
        }

        try {
            # set job_entry status to ingesting
            job_entry.set_status(ItemStatus.INGESTING);
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
                if page_numbers {
                    unique_pages = sorted(set(page_numbers));
                    if len(unique_pages) > 1 {
                        consolidated_page = f"{unique_pages[0]}-{unique_pages[-1]}";
                    } else {
                        consolidated_page = str(unique_pages[0]);
                    }
                } else {
                    consolidated_page = "1";
                }

                filtered_metadata = {
                    "source": metadata.get("docnm_kwd", ""),
                    "page": consolidated_page,
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
                if doc_entry {
                    # set doc entry status to ingesting
                    doc_entry.set_status(ItemStatus.INGESTING);
                    # filter out metadata keys that are not in the filtered_metadata
                    filtered_metadata.update(doc_entry.get_metadata());
                    # update the manifest entry with the consolidated metadata
                    doc_entry.set_metadata(filtered_metadata);
                }

                if( isinstance(doc_entry, DocURLEntry) ) {
                    # if the file is a URL, update the source in metadata
                    filtered_metadata["source"] = doc_entry.get_source();
                } else {
                    # compose the path to file and update source
                    srv_filename = f"ddc/{job_id}_{self.format_filename(filtered_metadata['filename'])}";
                    srv_source = self.get_agent().get_file_url(srv_filename);
                    if srv_source {
                        filtered_metadata["source"] = srv_source;
                    } else {
                        self.logger.error(f"Unable to get file source url for {filtered_metadata['filename']}, setting source to {filtered_metadata['filename']}");
                        filtered_metadata["source"] = filtered_metadata["filename"];
                    }
                }

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

    can get_callback_url(walker_name:str) -> str {
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

    can get_job(job_id:str) -> JobEntry {
        collection = self.get_collection();
        return (collection spawn _get_job_entry(job_id=job_id)).job_entry;
    }

    can list_doc_entries(page:int, limit:int) -> list[dict] {
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
        job_entry = self.get_job(job_id=job_id);

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
        job_entry = self.get_job(job_id=job_id);

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
                self.get_agent().delete_file(f"ddc/{job_id}_{self.format_filename(doc_entry.name)}");
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

    can delete_doc_job(job_id:str) -> bool {
        # Deletes all entries for a specific job ID from the document manifest and everywhere else.
        job_entry = self.get_job(job_id=job_id);

        if not job_entry {
            self.logger.error(f"Job ID {job_id} not found in doc manifest.");
            return False;
        }

        # iterate through and delete all document entries associated with the job ID
        doc_entries = job_entry.get_doc_entries();

        if not doc_entries {
            self.logger.info(f"No document entries found for job ID {job_id}. Removing job entry only.");
            # If no document entries, just remove the job entry
            job_entry.delete_job();
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
        job_entry = self.get_job(job_id=job_id);

        if not job_entry {
            self.logger.error(f"Job ID {job_id} not found in doc manifest.");
            return False;
        }

        # Retrieve the vector store action
        vector_store_action = self.get_agent().get_actions().get(action_label=self.vector_store_action);
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