"""This module contains the Streamlit app for the Typesense Vector Store Action"""

import streamlit as st
from jvcli.client.lib.utils import call_action_walker_exec
from jvcli.client.lib.widgets import app_controls, app_header, app_update_action
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
    with st.expander("Add Documents", False):
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

        # Process URLs into a list
        url_list = [url.strip() for url in doc_urls.split("\n") if url.strip()]

        # Validation message
        if not doc_uploads and not url_list:
            st.info("Please either upload files or provide URLs (or both)")

        if st.button("Upload", key=f"{model_key}_btn_queue_docs"):
            # Prepare the payload
            payload = {
                "urls": url_list if url_list else [],
                "from_page": 0,
                "to_page": 10000000,
                "lang": "english",
            }

            # Prepare files list (if any)
            if doc_uploads:
                files = []
                for selected_file in doc_uploads:
                    files.append(
                        (selected_file.name, selected_file.read(), selected_file.type)
                    )
            else:
                files = []

            # Call the parse_pdfs walker
            result = call_action_walker_exec(
                agent_id, module_root, "add_documents", payload, files
            )

            if result:
                # Display number of processed files
                total_processed = len(doc_uploads) + len(url_list)
                st.success(
                    f" {total_processed} document(s) queued for processing under job ID [ {result} ] "
                )
            else:
                st.error(
                    "Failed to process documents. Please check your inputs and try again."
                )

    # add app main controls
    app_controls(agent_id, action_id)

    # Add update button to apply changes
    app_update_action(agent_id, action_id)
