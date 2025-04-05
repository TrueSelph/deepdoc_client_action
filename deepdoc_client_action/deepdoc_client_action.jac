import:py os;
import:py requests;
import:py logging;
import:py traceback;
import:py from logging { Logger }
import:jac from jivas.agent.action.action { Action }
import:py from jvserve.lib.agent_interface { AgentInterface }
import:py from jvserve.lib.file_interface { file_interface }

node DeepDocClientAction :Action: {
    # Integrates with DeepDoc OCR and document parsing services to ingest documents into a vector store

    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    # api url to deepdoc service
    has api_url:str = os.environ.get('DEEPDOC_API_URL', 'https://deepdoc.trueselph.com');
    has api_key:str = os.environ.get('DEEPDOC_API_KEY','api-key');
    has base_url:str = os.environ.get('JIVAS_BASE_URL', '');
    has vector_store_action:str = "TypesenseVectorStoreAction";
    has doc_manifest:dict = {};

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

            # Make the POST request to the DeepDoc service
            response = requests.post(
                f"{self.api_url}/upload_and_chunk",
                files=files_data,
                data=payload
            );

            # Check if the response is successful
            if response.status_code != 200 {
                self.logger.error(f"Failed to queue documents: {response.text}");
                return "";
            }

            # Parse the response JSON
            response_data = response.json();
            if "job_id" in response_data {

                # now we archive the uploaded file(s) as under job_id in the doc_manifest
                for file in files {
                    if "name" in file {

                        output_file_name = f"{response_data['job_id']}_{file['name']}";
                        output_file_path = f"ddc/{output_file_name}";
                        file_interface.save_file(output_file_path, file["content"]);

                        srv_source = file_interface.get_file_url(f"ddc/{output_file_name}");

                        # Initialize the doc_manifest entry for the job_id if it does not exist
                        if response_data["job_id"] not in self.doc_manifest.keys() {
                            self.doc_manifest[response_data["job_id"]] = [];
                        }

                        # Append the file details to the doc_manifest entry
                        self.doc_manifest[response_data["job_id"]].append({
                            "file_path": srv_source or output_file_path,
                            "file_name": file["name"],
                            "file_type": file["type"]
                        });
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

    can get_deepdoc_job(job_id:str) -> dict {
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

    can cancel_deepdoc_job(job_id:str) -> bool {
        # """
        # Cancels a queued job in the DeepDoc service.

        # Args:
        #     job_id (str): The ID of the job to cancel.

        # Returns:
        #     bool: True if the cancellation was successful, False otherwise.
        # """
        try {
            # Make the DELETE request to cancel the job
            response = requests.delete(f"{self.api_url}/job/{job_id}");

            # Check if the response is successful
            if response.status_code != 200 {
                self.logger.error(f"Failed to cancel job: {response.text}");
                return False;
            }

            return True;
        } except Exception as e {
            self.logger.error(f"Exception occurred while cancelling job: {str(e)}");
            self.logger.error(traceback.format_exc());
            return False;
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
        try {
            # Ensure the job status is completed
            if job_data.get("status") != "completed" {
                self.logger.error("Job status is not 'completed'.");
                return False;
            }

            # Extract the result field from the job data
            results = job_data.get("result", []);
            if not results {
                self.logger.error("No results found in job data.");
                return False;
            }

                        # Get the vector store action and ingest the texts
            vector_store_action = self.get_agent().get_actions().get(action_label=self.vector_store_action);
            if not vector_store_action {
                self.logger.error(f"Vector store action '{self.vector_store_action}' not found.");
                return False;
            }

            # Prepare texts and metadatas and ingest
            for result in results {

                text = result.get("text", "");
                metadata = result.get("metadata", {});

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

                # compose the path to file and update source
                srv_filename = f"ddc/{job_id}_{filtered_metadata['filename']}";
                srv_source = file_interface.get_file_url(srv_filename);
                if srv_source {
                    filtered_metadata["source"] = srv_source;
                } else {
                    self.logger.error(f"Unable to get file source url for {filtered_metadata['filename']}, setting source to {filtered_metadata['filename']}");
                    filtered_metadata["source"] = filtered_metadata["filename"];
                }

                doc_id = vector_store_action.add_texts(
                    texts=[text],
                    metadatas=[filtered_metadata],
                    ids=[result.get("id") or f"doc_{os.urandom(8).hex()}"]
                );

                self.logger.info(f"{doc_id} added to vector store with metadata: {filtered_metadata}");
            }

            return True;

        } except Exception as e {
            self.logger.error(f"Exception occurred while importing job data: {str(e)}");
            self.logger.error(traceback.format_exc());
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


}