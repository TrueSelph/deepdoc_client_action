import os;
import re;
import requests;
import logging;
import traceback;
import from time { sleep }
import from typing { Optional }
import from collections { defaultdict }
import from logging { Logger }
import from jivas.agent.action.action { Action }
import from jvserve.lib.file_interface { file_interface }
import from jivas.agent.memory.collection { Collection }
import from actions.jivas.deepdoc_client_action.job_entry { JobEntry }
import from actions.jivas.deepdoc_client_action.doc_entry { DocEntry }
import from actions.jivas.deepdoc_client_action.doc_file_entry { DocFileEntry }
import from actions.jivas.deepdoc_client_action.doc_url_entry { DocURLEntry }
import from actions.jivas.deepdoc_client_action.item_status { ItemStatus }
import from .deepdoc_callback { deepdoc_callback }
import from jac_cloud.core.archetype {BaseCollection, NodeAnchor}
import from jivas.agent.modules.data.node_pager { NodePager }
import from jivas.agent.modules.data.node_get { node_get }
import from jivas.agent.modules.system.common { node_obj }
import from urllib.parse { urlparse, unquote, parse_qs }

node DeepDocClientAction(Action) {
    # Integrates with DeepDoc OCR and document parsing services to ingest documents into a vector store

    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    # api url to deepdoc service
    has api_url:str = os.environ.get('DEEPDOC_API_URL', '');
    has api_key:str = os.environ.get('DEEPDOC_API_KEY','api-key');
    has base_url:str = os.environ.get('JIVAS_BASE_URL', '');
    has vector_store_action:str = "TypesenseVectorStoreAction";
    has webhook_token_expiry_days:int = 1;

    def healthcheck() {
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

    def queue_job(
        urls:list[str]=[],
        files:list[dict]=[],
        metadatas:list[dict]=[],
        from_page:int=0,
        to_page:int=100000,
        lang:str="english",
        with_embeddings:bool=False,
        callback_url:str=""
    ) -> str {

        # """
        # Sends a request to the DeepDoc service to queue documents for processing.

        # Args:
        #     urls (list[str]): List of document URLs to process.
        #     files (list[dict]): List of file contents to process.
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
                "lang": lang,
                "with_embeddings": with_embeddings,  # default to False, can be overridden
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
                    job_entry = JobEntry(collection_id=collection.id, job_id = job_id);
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
                        output_filename = f"{job_id}_{self.sanitize_filename(name)}";
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
                        filename = self.extract_filename_from_url(url);
                        metadata["source"] = url;
                        metadata["filename"] = filename;
                        metadata["job_id"] = job_id;
                        job_entry.add_doc_url_entry(
                            name = filename,
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

    def get_job_status(job_id:str) -> dict {
        # """
        # Retrieves the status of a queued job from the DeepDoc service with retry logic.

        # Args:
        #     job_id (str): The ID of the job to check.

        # Returns:
        #     dict: The status and result of the job.
        # """
        max_retries = 3;
        retry_delay = 10;  # seconds between retries

        for attempt in range(0, max_retries + 1) {
            try {
                # Make the GET request to the DeepDoc service
                response = requests.get(f"{self.api_url}/job/{job_id}");

                self.logger.warning(f"{self.api_url}/job/{job_id} - {response.status_code}");

                # Check if the response is successful
                if response.status_code == 200 {
                    # Parse the response JSON
                    response_data = response.json();

                    # Ensure the response contains the expected fields
                    if "status" in response_data {
                        return response_data;
                    } else {
                        self.logger.error("Response does not contain 'status' field.");
                        # Don't retry for invalid response format, return error immediately
                        return {"status": "error", "error": "Invalid response format"};
                    }
                }

                # If not successful and not the last attempt, retry
                if attempt < max_retries {
                    self.logger.warning(f"Attempt {attempt + 1} failed with status {response.status_code}. Retrying in {retry_delay} seconds...");
                    sleep(retry_delay);
                    continue;
                }

                # If this was the last attempt and still failed
                self.logger.error(f"Failed to get job [{job_id}] status after {max_retries + 1} attempts: {response.text}");
                return {"status": "error", "error": response.text};

            } except Exception as e {
                # Handle network errors and other exceptions
                if attempt < max_retries {
                    self.logger.warning(f"Attempt {attempt + 1} failed with exception: {str(e)}. Retrying in {retry_delay} seconds...");
                    sleep(retry_delay);
                    continue;
                }

                self.logger.error(f"Exception occurred while getting job status after {max_retries + 1} attempts: {str(e)}");
                self.logger.error(traceback.format_exc());
                return {"status": "error", "error": str(e)};
            }
        }
    }

    def cancel_job(job_id:str) -> dict {
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

    def ingest_job(job_id:str, job_data:dict) -> bool {
        # """
        # Imports the results of a completed job into the vector store using add_texts.

        # Args:
        #     job_data (dict): The data returned from the DeepDoc service for the completed job.

        # Returns:
        #     bool: True if the import was successful, False otherwise.
        # """

        # Validate job status
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

        # Extract results
        results = job_data.get("result", []);
        if not results {
            self.logger.error("No results found in job data.");
            job_entry = self.get_job_entry(job_id=job_id);
            job_entry.set_status(ItemStatus.FAILED);
            return False;
        }

        # Get vector store action
        vector_store_action = self.get_agent().get_action(action_label=self.vector_store_action);
        if not vector_store_action {
            self.logger.error(f"Vector store action '{self.vector_store_action}' not found.");
            job_entry = self.get_job_entry(job_id=job_id);
            job_entry.set_status(ItemStatus.FAILED);
            return False;
        }

        # Get job entry
        job_entry = self.get_job_entry(job_id=job_id);
        if not job_entry {
            self.logger.error(f"Job entry '{job_id}' not found.");
            return False;
        }

        try {
            job_entry.set_status(ItemStatus.INGESTING);
            success = True;

            # Group results by document filename
            documents = defaultdict(list);
            for result in results {
                filename = result.get("metadata", {}).get("original_filename", "");
                documents[filename].append(result);
            }

            # Process each document in batch
            for (filename, doc_results) in documents.items() {
                doc_success = False;
                try {
                    # Get document entry
                    doc_entry = job_entry.get_doc_entry_by_name(filename);
                    if not doc_entry {
                        self.logger.error(f"No document entry found for filename: {filename}");
                        success = False;
                        continue;
                    }
                    self.logger.info(f"Ingesting document: {filename} with {len(doc_results)} chunks.");
                    doc_entry.set_status(ItemStatus.INGESTING);
                    doc_metadata = doc_entry.get_metadata();
                    doc_metadata.update({
                        "filename": filename,
                        "source": doc_entry.get_source(),
                        "job_id": job_id
                    });

                    # Prepare batch data
                    ids = [];
                    chunk_ids = [];
                    texts = [];
                    metadatas = [];
                    embeddings = [];
                    page_numbers = [];

                    for result in doc_results {
                        text = result.get("text", "");
                        if not text {
                            self.logger.error(f"Empty text in result: {result}");
                            continue;
                        }

                        # Process page numbers
                        result_page_nums = result.get("metadata", {}).get("page_num_int", []);
                        page_numbers.extend(result_page_nums);

                        # Prepare chunk metadata
                        chunk_metadata = doc_metadata.copy();
                        chunk_metadata["page"] = self.format_page_range(result_page_nums);
                        # Process bbox, if present
                        chunk_metadata["bbox"] = result.get("metadata", {}).get("bbox", []);
                        # Add to batch
                        texts.append(text);
                        metadatas.append(chunk_metadata);
                        ids.append(result.get("id") or f"chunk_{os.urandom(8).hex()}");

                        # add embeddings to batch if available
                        if "embeddings" in result {
                            embeddings.append(result.get("embeddings", []));
                        }
                    }

                    # Ingest batch
                    if texts {

                        if embeddings {
                            # Add texts with embeddings
                            chunk_ids = vector_store_action.add_texts_with_embeddings(
                                texts=texts,
                                metadatas=metadatas,
                                ids=ids,
                                embeddings=embeddings
                            );

                        } else {
                            # Add texts without embeddings
                            chunk_ids = vector_store_action.add_texts(
                                texts=texts,
                                metadatas=metadatas,
                                ids=ids
                            );
                        }

                        if not chunk_ids {
                            self.logger.error(f"Failed to add texts to vector store for document: {filename}");
                            success = False;
                            continue;
                        }

                        # Update document with chunk IDs
                        for chunk_id in chunk_ids {
                            doc_entry.add_chunk_id(chunk_id);
                        }

                        # Update document page range
                        if page_numbers {
                            doc_entry.add_metadata("page", self.format_page_range(page_numbers));
                        }

                        doc_success = True;
                    }
                } except Exception as e {
                    self.logger.error(f"Document processing failed ({filename}): {str(e)}");
                    self.logger.error(traceback.format_exc());
                    success = False;
                } finally {
                    if not doc_entry {
                        continue;
                    }
                    doc_entry.set_status(ItemStatus.COMPLETED if doc_success else ItemStatus.FAILED);
                }

            }
            # Finalize job status
            job_entry.set_status(ItemStatus.COMPLETED if success else ItemStatus.FAILED);
            return success;

        } except Exception as e {
            self.logger.error(f"Exception occurred while importing job data: {str(e)}");
            self.logger.error(traceback.format_exc());
            job_entry.set_status(ItemStatus.FAILED);
            return False;
        }
    }

    def extract_filename_from_url(url: str) -> str {
        #*
        Extract filename from URL with proper handling of query strings, Google Drive links, etc.

        Args:
            url: The URL to extract filename from

        Returns:
            Extracted filename with proper extension
        *#

        parsed = urlparse(url);
        # Handle URLs with query parameters
        path = parsed.path;
        query = parsed.query;

        # Handle Google Drive URLs specifically
        if 'drive.google.com' in url or 'docs.google.com' in url {
            return self.extract_google_drive_filename(url);
        }

        # Extract filename from path
        filename = unquote(os.path.basename(path)) if path else f"download_{hash(url) % 10000}";

        # If filename is empty or generic, try to get from query parameters
        if not filename or filename in ['', 'download', 'file', 'document'] {
            filename = self.extract_filename_from_query(query, url);
        }

        # Ensure we have a valid filename
        if not filename or '.' not in filename {
            filename = self.generate_safe_filename(url);
        }

        return self.sanitize_filename(filename);
    }

    def extract_google_drive_filename(url: str) -> str {
        # Extract filename from Google Drive URL
        filename = '';
        file_id_match = re.search(r'/d/([a-zA-Z0-9_-]+)', url) or re.search(r'id=([a-zA-Z0-9_-]+)', url);

        if not file_id_match {
            filename = self.generate_safe_filename(url);
        } else {
            filename = file_id_match.group(1);
        }

        return self.sanitize_filename(filename);
    }

    def extract_filename_from_query(query: str, url: str) -> str {
        # Try to extract filename from query parameters
        query_params = parse_qs(query);

        # Common query parameter names that might contain filenames
        filename_params = ['filename', 'file', 'name', 'download', 'doc', 'document'];

        for param in filename_params {
            if param in query_params {
                filename = query_params[param][0];
                if filename and '.' in filename {  # Likely has extension
                    return filename;
                }
            }
        }

        # Check for common file extension patterns in the entire URL
        extension_pattern = r'\.(pdf|docx?|xlsx?|pptx?|txt|jpg|jpeg|png|gif|bmp|zip|rar|7z)';
        extension_match = re.search(extension_pattern, url, re.IGNORECASE);
        if extension_match {
            ext = extension_match.group(1);
            return f"document_{hash(url) % 10000}.{ext.lower()}";
        }

        return None;
    }

    def generate_safe_filename(url: str) -> str {
        # Generate a safe filename based on URL and response headers
        parsed = urlparse(url);

        # Try to guess from URL path
        if parsed.path {
            # Look for common file extensions in the path
            extension_pattern = r'\.([a-zA-Z0-9]{2,5})$';
            extension_match = re.search(extension_pattern, parsed.path);
            if extension_match {
                ext = extension_match.group(1);
                return f"document_{hash(url) % 10000}.{ext.lower()}";
            }
        }

        # Final fallback
        return f"download_{hash(url) % 10000}.bin";
    }

    def sanitize_filename(filename: str) -> str {
        # Sanitize filename to remove invalid characters

        # Remove invalid characters for filenames
        invalid_chars = ['<', '>', ':', '"', '/', '\\', '|', '?', '*', "'", '"'];
        for char in invalid_chars {
            filename = filename.replace(char, '_');
        }

        # Remove multiple underscores and trim
        filename = re.sub(r'_+', '_', filename).strip('_');

        # Ensure filename is not too long
        if len(filename) > 200 {
            (name, ext) = os.path.splitext(filename);
            filename = name[:200-len(ext)] + ext;
        }

        return filename;
    }

    def format_page_range(page_list:list[int]) -> str {
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

    def generate_callback_url() -> str {
        # setup procedure for webhook registration on deepdoc

        base_url = self.base_url;
        agent_id = self.get_agent().id;

        # generate webhook key
        webhook_walker = deepdoc_callback(agent_id=agent_id);
        callback_url = webhook_walker.get_callback_url(
            base_url=self.base_url,
            agent_id=agent_id,
            expiration = self.webhook_token_expiry_days
        );

        if(callback_url) {
            return callback_url;
        } else {
            self.logger.error('unable to generate webhook url for DeepDoc Client, missing required parameters');
            return "";
        }

    }

    def get_job_entry(job_id:str) -> Optional[JobEntry] {
        # Retrieves a job entry by job_id from the collection.
        collection = self.get_collection();

        job_entry = node_obj(node_get({
            "name": "JobEntry",
            "archetype.collection_id": collection.id,
            "archetype.job_id": job_id
        }));

        return job_entry;
    }

    def list_doc_entries(page:int, limit:int) -> list[dict] {
        # Lists all document entries in the manifest with pagination.

        collection = self.get_collection();
        # Initialize pager
        pager = NodePager(NodeAnchor.Collection, page_size=limit, current_page=page);

        # Get a page of results
        items = pager.get_page({
            "$or": [
            {"$and": [{"name": "DocFileEntry"}, {"archetype.collection_id": collection.id}]},
            {"$and": [{"name": "DocURLEntry"}, {"archetype.collection_id": collection.id}]}
            ]
        });

        if not items {
            return {};
        }

        # call export on each and convert it to a dict
        items = [item.export() for item in items];
        # get all info as a dict
        pagination_info = pager.to_dict();

        return {
            "page": page,
            "limit": limit,
            "total_items": pagination_info.get("total_items", 0),
            "total_pages": pagination_info.get("total_pages", 1),
            "has_previous": pagination_info.get("has_previous", False),
            "has_next": pagination_info.get("has_next", False),
            "items": items
        };
    }

    def get_doc_entry(job_id:str, doc_id:str) -> dict {
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

    def delete_doc_entry(job_id:str, doc_id:str) -> bool {
        # Deletes a specific entry from the document manifest for a given job ID.
        # set manifest_only to True to delete the entry from the manifest only and not the file system

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
                self.delete_file(f"{job_id}_{self.sanitize_filename(doc_entry.name)}");
            } except Exception as e {
                self.logger.error(f"Failed to delete file from filesystem: {str(e)}");
            }
        }

        # remove any vector store entries associated with the file
        self.remove_doc_vector_store_entries(job_id=job_id, doc_id=doc_id);
        # finally remove the doc entry from the job.. and the entire job if it's the last entry
        if job_entry.delete_doc_entry(doc_id) {
            return True;
        }

        return False;
    }

    def delete_job_entry(job_id:str) -> bool {
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

    def remove_doc_vector_store_entries(job_id:str, doc_id:str) -> bool {
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

    def export_collection() -> dict {
        collection = self.get_collection();
        export_collection = collection spawn _export_collection();
        return {"documents": export_collection.documents};
    }

    def import_collection(data:dict, purge:bool=True) -> bool {
        if purge {
            self.get_agent().get_memory().purge_collection_memory(self.label);
        }
        collection = self.get_collection();

        if data {
            documents = data.get("documents");
            import_collection = collection spawn _import_collection(documents=documents);
            return True;
        }
        return False;
    }

}

walker _get_job_entry {
    # spawns on action collection and finds a job by job_id

    has job_id:str = "";
    has job_entry:JobEntry = None;

    obj __specs__ {
        static has private: bool = True;
    }

    can on_collection with Collection entry {
        visit [-->](`?JobEntry)(?job_id == self.job_id);
    }

    can on_job_entry with JobEntry entry {
        self.job_entry = here;
    }

}


walker _export_collection {
    has documents:dict = {};

    obj __specs__ {
        static has private:bool = True;
    }

    can on_collection with Collection entry {
        visit [-->](`?JobEntry);
    }

    can on_job_entry with JobEntry entry {
        visit [-->];
    }

    can on_doc_file_entry with DocFileEntry entry {
        job_entry_id = [<--](`?JobEntry)[0].job_id;
        if job_entry_id not in self.documents {
            self.documents[job_entry_id] = [here.export()];
        } else {
            self.documents[job_entry_id].append(here.export());
        }
    }

    can on_doc_url_entry with DocURLEntry entry {
        job_entry_id = [<--](`?JobEntry)[0].job_id;
        if job_entry_id not in self.documents {
            self.documents[job_entry_id] = [here.export()];
        } else {
            self.documents[job_entry_id].append(here.export());
        }
    }

}

walker _import_collection {
    has documents:dict = {};

    obj __specs__ {
        static has private:bool = True;
    }

    can on_collection with Collection entry {
        for job_id in self.documents {
            visit [-->](`?JobEntry)(?job_id == job_id) else {
                job_entry = JobEntry(collection_id=here.id, job_id=job_id);
                here ++> job_entry;

                for document_entry in self.documents[job_id] {
                    if document_entry.get("mimetype") == "url"{

                        doc_url_entry = DocURLEntry(
                            collection_id = here.id,
                            job_id = job_id,
                            status = ItemStatus.PENDING if not job_id else ItemStatus.PROCESSING,
                            name = document_entry.get("name"),
                            source = document_entry.get("source"),
                            metadata = document_entry.get("metadata")
                        );

                        # now we attach it to the job
                        job_entry ++> doc_url_entry;

                    } else {
                        doc_file_entry = DocFileEntry(
                            collection_id = here.id,
                            job_id = job_id,
                            status = ItemStatus.PENDING if not job_id else ItemStatus.PROCESSING,
                            name = document_entry.get("name"),
                            source = document_entry.get("source"),
                            mimetype = document_entry.get("mimetype"),
                            metadata = document_entry.get("metadata")
                        );
                        # now we attach it to the job
                        job_entry ++> doc_file_entry;
                    }
                }

            }
        }
    }

    can on_job_entry with JobEntry entry {
        for document_entry in self.documents[here.job_id] {
            if document_entry.get("mimetype") == "url" and not [-->](`?DocURLEntry)(?name == document_entry.get("name")){

                doc_url_entry = DocURLEntry(
                    collection_id = here.collection_id,
                    job_id = here.job_id,
                    status = ItemStatus.PENDING if not here.job_id else ItemStatus.PROCESSING,
                    name = document_entry.get("name"),
                    source = document_entry.get("source"),
                    metadata = document_entry.get("metadata")
                );

                # now we attach it to the job
                here ++> doc_url_entry;

            } elif not [-->](`?DocFileEntry)(?name == document_entry.get("name")) {
                doc_file_entry = DocFileEntry(
                    collection_id = here.collection_id,
                    job_id = here.job_id,
                    status = ItemStatus.PENDING if not here.job_id else ItemStatus.PROCESSING,
                    name = document_entry.get("name"),
                    source = document_entry.get("source"),
                    mimetype = document_entry.get("mimetype"),
                    metadata = document_entry.get("metadata")
                );
                # now we attach it to the job
                here ++> doc_file_entry;
            }
        }
    }
}