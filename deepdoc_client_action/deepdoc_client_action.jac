import:py os;
import:py logging;
import:py traceback;
import:py from logging { Logger }
import:jac from agent.action.action { Action }
import:py from jvserve.lib.agent_interface { AgentInterface }

node DeepDocClientAction :Action: {
    # Integrates with DeepDoc OCR and document parsing services to ingest documents into a vector store

    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    # api url to deepdoc service
    has deepdoc_api_url:str = "";
    has vector_store_action:str = "TypesenseVectorStoreAction";
    has doc_manifest:str = [];

    can queue_deepdoc_job(
        urls:list[str]=[],
        files:list[bytes]=[],
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

            # Prepare the files and URLs for the request
            files_data = [("files", (f"file_{i}", file, "application/octet-stream")) for (i, file) in enumerate(files)];
            data = [("urls", url) for url in urls];

            # Combine payload, files, and URLs
            multipart_data = data + list(payload.items()) + files_data;

            # Make the POST request to the DeepDoc service
            response = requests.post(
                f"{self.deepdoc_api_url}/upload_and_chunk",
                files=multipart_data
            );

            # Check if the response is successful
            if response.status_code != 200 {
                self.logger.error(f"Failed to queue documents: {response.text}");
                return "";
            }

            # Parse the response JSON
            response_data = response.json();
            if "job_id" in response_data {
                return response_data["job_id"];
            } else {
                self.logger.error("Response does not contain job_id.");
                return "";
            }
        } catch Exception as e {
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
            response = requests.get(f"{self.deepdoc_api_url}/job/{job_id}");

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
        } catch Exception as e {
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
            response = requests.delete(f"{self.deepdoc_api_url}/job/{job_id}");

            # Check if the response is successful
            if response.status_code != 200 {
                self.logger.error(f"Failed to cancel job: {response.text}");
                return False;
            }

            return True;
        } catch Exception as e {
            self.logger.error(f"Exception occurred while cancelling job: {str(e)}");
            self.logger.error(traceback.format_exc());
            return False;
        }
    }

    can ingest_deepdoc_job(job_data:dict) -> bool {
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

            # Prepare texts and metadatas for ingestion
            texts = [];
            metadatas = [];
            for result in results {
                text = result.get("text", "");
                metadata = result.get("metadata", {});

                # Ensure required metadata fields are retained
                page_numbers = metadata.get("page_num_int", []);
                consolidated_page = page_numbers[0] if page_numbers else None;

                filtered_metadata = {
                    "page": consolidated_page,
                    "source": metadata.get("docnm_kwd", "")
                };

                texts.append(text);
                metadatas.append(filtered_metadata);
            }

            # Get the vector store action and ingest the texts
            vector_store_action = self.get_agent().get_actions().get(action_label=self.vector_store_action);
            if not vector_store_action {
                self.logger.error(f"Vector store action '{self.vector_store_action}' not found.");
                return False;
            }

            vector_store_action.add_texts(texts=texts, metadatas=metadatas);

            return True;
        } catch Exception as e {
            self.logger.error(f"Exception occurred while importing job data: {str(e)}");
            self.logger.error(traceback.format_exc());
            return False;
        }
    }

    can get_callback_url(walker_name:str) -> str {
        # setup procedure for webhook registration on deepdoc

        base_url = os.environ.get('JIVAS_BASE_URL');
        callback_url = "";

        agent_id = self.get_agent().id;
        module_root = self.get_module_root();
        # generate webhook key
        webhook_key = AgentInterface.encrypt_webhook_key(agent_id=agent_id, module_root=module_root, walker=walker_name);

        if(base_url and webhook_key) {
            # complete the full webhook url
            callback_url = f'{base_url}/webhook/{webhook_key}';
            self.logger.debug(f'webhook url: {self.webhook_url}');
        } else {
            self.logger.error('unable to generate webhook url for DeepDoc Client, missing required parameters');
            return "";
        }

        return callback_url;
    }


}