"""This module contains the Streamlit app for the Typesense Vector Store Action"""

import time
from datetime import datetime

import streamlit as st
from jvcli.client.lib.utils import call_action_walker_exec
from jvcli.client.lib.widgets import app_header, app_update_action
from streamlit_router import StreamlitRouter


def render(router: StreamlitRouter, agent_id: str, action_id: str, info: dict) -> None:
    """
    Renders a paginated list of documents.

    :param agent_id: The agent ID.
    :param action_id: The action ID.
    :param info: Additional information.
    """
    (model_key, module_root) = app_header(agent_id, action_id, info)

    # add documents section
    with st.expander("Configure", False):
        # add a field for API URL
        st.session_state[model_key]["api_url"] = st.text_input(
            "API URL",
            value=st.session_state[model_key]["api_url"],
            help="Enter the API URL for the DeepDoc service",
            key="api_url",
        )
        # add a field for API Key
        st.session_state[model_key]["api_key"] = st.text_input(
            "API Key",
            value=st.session_state[model_key]["api_key"],
            help="Enter the API Key for the DeepDoc service",
            type="password",
            key="api_key",
        )
        # add a field for base url
        st.session_state[model_key]["base_url"] = st.text_input(
            "Base URL",
            value=st.session_state[model_key]["base_url"],
            help="Enter the base URL for the JIVAS instance",
            key="base_url",
        )
        # add a field for the vector store action
        st.session_state[model_key]["vector_store_action"] = st.text_input(
            "Vector Store Action",
            value=st.session_state[model_key]["vector_store_action"],
            help="Enter the vector store action name",
            key="vector_store_action",
        )
        # Add update button to apply changes
        app_update_action(agent_id, action_id)

    # add documents section
    with st.expander("Add Documents", True):
        # File upload section
        doc_uploads = st.file_uploader(
            "Upload documents",
            type=["pdf", "docx", "doc", "txt", "pptx", "ppt"],
            accept_multiple_files=True,
            key=f"{model_key}_doc_uploads",
        )

        # URL input section
        doc_urls = st.text_area(
            "Enter document URLs (one per line)",
            height=100,
            help="Enter URLs to document files, one URL per line",
            key=f"{model_key}_doc_urls",
        )

        metadatas = st.text_area(
            "Enter metadata (JSON format, one per line)",
            height=150,
            help="Example: {'author': 'John Doe', 'category': 'Finance'}",
            key=f"{model_key}_metadatas",
        )

        # Custom parameters section
        from_page = st.number_input(
            "From Page",
            min_value=0,
            value=0,
            help="Specify the starting page number for processing",
            key=f"{model_key}_from_page",
        )
        to_page = st.number_input(
            "To Page",
            min_value=1,
            value=100000,
            help="Specify the ending page number for processing",
            key=f"{model_key}_to_page",
        )
        lang = st.text_input(
            "Language",
            value="english",
            help="Specify the language of the documents",
            key=f"{model_key}_lang",
        )

        # Process inputs
        url_list = [url.strip() for url in doc_urls.split("\n") if url.strip()]
        metadata_list = []
        if metadatas.strip():
            try:
                metadata_list = [
                    eval(line.strip()) for line in metadatas.split("\n") if line.strip()
                ]
                if len(metadata_list) != len(doc_uploads) + len(url_list):
                    st.warning(
                        "The number of metadata entries must match the total number of documents (uploaded + URLs)."
                    )
            except Exception as e:
                st.error(f"Invalid metadata format: {e}")

        # Validation message
        if not doc_uploads and not url_list:
            st.info("Upload files and/or provide file URLs")

        if st.button("Upload", key=f"{model_key}_btn_queue_docs"):
            # Prepare the payload
            payload = {
                "urls": url_list if url_list else [],
                "metadatas": metadata_list if metadata_list else [],
                "from_page": from_page,
                "to_page": to_page,
                "lang": lang,
            }

            # Prepare files list (if any)
            files = []
            if doc_uploads:
                for selected_file in doc_uploads:
                    files.append(
                        (selected_file.name, selected_file.read(), selected_file.type)
                    )

            # Call the parse_pdfs walker
            result = call_action_walker_exec(
                agent_id, module_root, "add_documents", payload, files
            )

            if result:
                # Display number of processed files
                total_processed = len(doc_uploads) + len(url_list)
                st.success(
                    f"{total_processed} document(s) submitted for processing under job ID [ {result} ]"
                )
            else:
                st.error(
                    "Failed to process documents. Please check your inputs and try again."
                )

    # add document list section
    with st.expander("Document List", True):
        # Fetch the document list
        document_list = call_action_walker_exec(agent_id, module_root, "list_documents")

        if document_list:
            # Check if any documents are still processing
            any_processing = any(not doc.get("chunk_ids") for doc in document_list)

            # Group documents by job_id
            jobs: dict = {}
            for document in document_list:
                job_id = document["job_id"]
                if job_id not in jobs:
                    jobs[job_id] = []
                jobs[job_id].append(document)

            # Display documents grouped by job_id
            for job_id, documents in jobs.items():
                # Check if any document in this job is still processing (no chunk_ids)
                has_processing = any(not doc.get("chunk_ids") for doc in documents)

                st.subheader(f"Job: {job_id}")

                # Display cancel button for the entire job if any documents are processing
                if has_processing and st.button(
                    "Cancel Job", key=f"cancel_job_{job_id}"
                ):
                    # Prepare arguments for cancellation - all processing documents in this job
                    args = {
                        "documents": [
                            {
                                "job_id": doc["job_id"],
                                "filename": doc["filename"],
                            }
                            for doc in documents
                            if not doc.get("chunk_ids")
                        ]
                    }
                    # Call the cancel_documents walker
                    cancel_result = call_action_walker_exec(
                        agent_id, module_root, "cancel_documents", args
                    )
                    if cancel_result:
                        st.rerun()
                        st.success(f"Job {job_id} cancelled successfully.")
                    else:
                        st.error(f"Failed to cancel job {job_id}.")

                # Display each document in the job
                for index, document in enumerate(documents, start=1):
                    col1, col2, col3, col4 = st.columns([4, 4, 2, 1])
                    with col1:
                        # Display document name as a hyperlink if file_path has a value
                        if document.get("file_path"):
                            st.markdown(
                                f"[{document['filename']}]({document['file_path']})",
                                unsafe_allow_html=True,
                            )
                        else:
                            st.text(document["filename"])
                    with col2:
                        # Display metadata if available
                        metadata = document.get("metadata", {})
                        if metadata:
                            st.json(metadata)
                        else:
                            st.text("No Metadata")
                    with col3:
                        # Display file type
                        st.text(document["file_type"])
                    with col4:
                        # Show "Delete" button if chunk_ids is not empty, otherwise show "Processing"
                        if document.get("chunk_ids"):
                            if st.button(
                                "Delete",
                                key=f"delete_{index}_{document['job_id']}_{document['filename']}",
                            ):
                                # Prepare arguments for deletion
                                args = {
                                    "documents": [
                                        {
                                            "job_id": document["job_id"],
                                            "filename": document["filename"],
                                        }
                                    ]
                                }
                                # Call the delete_documents walker
                                delete_result = call_action_walker_exec(
                                    agent_id, module_root, "delete_documents", args
                                )
                                if delete_result:
                                    st.rerun()
                                    st.success(
                                        f"Document {document['filename']} deleted successfully."
                                    )
                                else:
                                    st.error(
                                        f"Failed to delete document {document['filename']}."
                                    )
                        else:
                            st.text("Processing")

                st.divider()  # Add a divider between job groups

            # Display last refresh time
            last_refresh = datetime.now().strftime("%H:%M:%S")
            refresh_status = st.empty()
            refresh_status.caption(f"Last refreshed: {last_refresh}")

            # Auto-refresh every 3 seconds if any documents are processing
            if any_processing:
                time.sleep(3)
                st.rerun()

        else:
            st.info("No documents found. Your uploaded documents will be shown here.")
