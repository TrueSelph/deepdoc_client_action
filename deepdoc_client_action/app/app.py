"""This module contains the Streamlit app for the Typesense Vector Store Action"""

import io
import json
import time
from datetime import datetime
from typing import Dict

import streamlit as st
import yaml
from jvclient.lib.utils import call_api, get_reports_payload
from jvclient.lib.widgets import app_header, app_update_action
from streamlit_router import StreamlitRouter


def render(router: StreamlitRouter, agent_id: str, action_id: str, info: dict) -> None:
    """
    Renders a paginated list of documents.

    :param agent_id: The agent ID.
    :param action_id: The action ID.
    :param info: Additional information.
    """
    (model_key, module_root) = app_header(agent_id, action_id, info)
    if "job_id_details" not in st.session_state:
        st.session_state.job_id_details = ""
    if "editing_doc_id" not in st.session_state:
        st.session_state.editing_doc_id = None

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
        # add a field for the vector store action
        with_embeddings = st.toggle(
            "Process with Embeddings",
            key="with_embeddings",
            help="Toggle on if you want to process documents with embeddings",
            value=True,
        )

        chunker_type = st.selectbox(
            "Chunker type",
            options=["mineru", "toc", "hybrid", "hierarchical"],
            key=f"{model_key}_chunker_type",
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
            # Validate required inputs
            if not agent_id:
                st.error("Agent ID is required")
                st.stop()

            # Ensure at least one document source is provided
            if not doc_uploads and not url_list:
                st.error("Please provide either files or URLs")
                st.stop()

            # Build the JSON body structure
            body_payload = {
                "agent_id": str(agent_id),
                "from_page": int(from_page) if from_page is not None else 0,
                "to_page": int(to_page) if to_page is not None else 0,
                "lang": str(lang),
                "with_embeddings": with_embeddings,
                "chunker_type": chunker_type,
            }

            # Add optional fields only if they exist
            if url_list:
                body_payload["urls"] = url_list
            if metadata_list:
                body_payload["metadatas"] = metadata_list

            # Create a JSON file in memory for the body
            body_json = json.dumps(body_payload)
            body_file = io.BytesIO(body_json.encode("utf-8"))

            # Prepare the files list
            files = [("body", ("body.json", body_file, "application/json"))]

            # Add document files if any
            if doc_uploads:
                for selected_file in doc_uploads:
                    # Use correct MIME type or fallback
                    mime_type = selected_file.type or "application/octet-stream"
                    files.append(
                        (
                            "files",
                            (selected_file.name, selected_file.getvalue(), mime_type),
                        )
                    )

            # API call with proper error handling
            try:
                result = call_api(
                    endpoint="action/walker/deepdoc_client_action/add_documents",
                    files=files,
                    timeout=120,
                )
                if result.status_code == 422:
                    error_detail = result.json().get(
                        "detail", "Unknown validation error"
                    )
                    st.error(f"Validation error: {error_detail}")
                elif result.status_code >= 400:
                    st.error(f"API Error ({result.status_code}): {result.text}")

            except Exception as e:
                st.error(f"Connection failed: {str(e)}")
            finally:
                # Close the in-memory file
                body_file.close()

            if result and result.status_code == 200:
                payload = get_reports_payload(result)

                if payload:
                    # Display number of processed files
                    total_processed = len(doc_uploads) + len(url_list)
                    st.success(
                        f"{total_processed} document(s) submitted for processing under job ID [{payload}]"
                    )
                else:
                    st.error("No job ID returned from the API. Please try again.")
            else:
                st.error(
                    "Failed to process documents. Please check your inputs and try again."
                )

    def format_datetime(dt_str: str) -> str:
        """Format datetime string to short date and time format

        Args:
            dt_str: The datetime string to format

        Returns:
            Formatted datetime string or empty string if input is empty
        """
        if not dt_str:
            return ""
        dt = datetime.fromisoformat(dt_str.replace("Z", "+00:00"))
        return dt.strftime("%Y-%m-%d %H:%M:%S")

    def calculate_processing_time(created_str: str, completed_str: str) -> str:
        """Calculate processing time between created and completed datetimes

        Args:
            created_str: The creation datetime string
            completed_str: The completion datetime string

        Returns:
            Formatted processing time as HH:MM:SS or empty string if inputs are invalid
        """
        if not created_str or not completed_str:
            return ""

        created = datetime.fromisoformat(created_str.replace("Z", "+00:00"))
        completed = datetime.fromisoformat(completed_str.replace("Z", "+00:00"))
        delta = completed - created

        # Format as HH:MM:SS
        total_seconds = int(delta.total_seconds())
        hours, remainder = divmod(total_seconds, 3600)
        minutes, seconds = divmod(remainder, 60)
        return f"{hours:02d}:{minutes:02d}:{seconds:02d}"

    def get_status_badge(status: str) -> str:
        """Return a colored badge for the status

        Args:
            status: The status string to display

        Returns:
            HTML span element with colored badge styling
        """
        status = str(status).upper()
        color_map: Dict[str, str] = {
            "COMPLETED": "green",
            "PROCESSING": "orange",
            "INGESTING": "orange",
            "PENDING": "blue",
            "FAILED": "red",
            "CANCELLED": "gray",
        }
        color = color_map.get(status, "gray")
        return f"<span style='background-color: {color}; color: white; padding: 2px 6px; border-radius: 4px;'>{status}</span>"

    with st.expander("Export document", False):
        # Fetch documents with pagination parameters
        with_embeddings = st.toggle(
            "Export with Embeddings", value=True, key=f"{model_key}_with_embeddings"
        )

        if st.button("Export Documents", key=f"{model_key}_export_btn"):
            result = call_api(
                endpoint="action/walker/deepdoc_client_action/export_documents",
                json_data={
                    "agent_id": agent_id,
                    "reporting": True,
                    "with_embeddings": with_embeddings,
                },
                timeout=120,
            )

            if result and result.status_code == 200:
                payload = get_reports_payload(result)
                if payload:
                    st.download_button(
                        label="Download Documents",
                        data=json.dumps(payload, indent=2, ensure_ascii=False),
                        file_name="deepdoc_documents.json",
                        mime="application/json",
                    )
                else:
                    st.error("No job ID returned from the API. Please try again.")

    with st.expander("Import document", False):
        knode_source = st.radio(
            "Choose data source:",
            ("Text input", "Upload file"),
            key=f"{model_key}_knode_source",
        )

        purge_collection = st.toggle(
            "Purge Collection",
            value=False,
            key=f"{model_key}_purge_collection",
        )

        data_to_import = ""
        if knode_source == "Text input":
            data_to_import = st.text_area(
                "Document in YAML or JSON",
                value="",
                height=170,
                key=f"{model_key}_knode_data",
            )

        uploaded_file = None
        if knode_source == "Upload file":
            uploaded_file = st.file_uploader(
                "Upload file (YAML or JSON)",
                type=["yaml", "json"],
                key=f"{model_key}_document_upload",
            )

        with_embeddings = st.toggle(
            "Import with Embeddings",
            value=True,
            key=f"{model_key}_import_embeddings",
        )

        if st.button("Import", key=f"{model_key}_btn_import_document"):
            if uploaded_file:
                try:
                    file_content = uploaded_file.read().decode(
                        "utf-8", errors="replace"
                    )
                    if uploaded_file.type == "application/json":
                        data_to_import = json.loads(file_content)
                    else:
                        data_to_import = yaml.safe_load(file_content)
                    data_to_import = json.dumps(data_to_import, ensure_ascii=False)
                except Exception as e:
                    st.error(f"Error loading file: {e}")

            if data_to_import:
                result = call_api(
                    endpoint="action/walker/deepdoc_client_action/import_documents",
                    json_data={
                        "agent_id": agent_id,
                        "data": data_to_import,
                        "with_embeddings": with_embeddings,
                        "purge": purge_collection,
                    },
                )

                if result:
                    st.success("Agent documents imported successfully")
                else:
                    st.error(
                        "Failed to import document. Ensure valid YAML/JSON format."
                    )
            else:
                st.error(
                    "No data to import. Please provide valid text or upload a file."
                )

    with st.expander("Document List", True):
        # Initialize session state variables for pagination
        if "current_page" not in st.session_state:
            st.session_state.current_page = 1
        if "per_page" not in st.session_state:
            st.session_state.per_page = 25

        # Initialize confirmation states
        if "confirm_state" not in st.session_state:
            st.session_state.confirm_state = {
                "active": False,
                "type": None,
                "job_id": None,
                "filename": None,
            }

        # Pagination controls at the top
        col1, col2, col3 = st.columns([2, 4, 2])
        with col1:
            # Per-page selection dropdown
            per_page = st.selectbox(
                "Items per page",
                options=[1, 5, 10, 25, 50, 100],
                index=[1, 5, 10, 25, 50, 100].index(st.session_state.per_page),
                key="per_page_selector",
                on_change=lambda: setattr(st.session_state, "current_page", 1),
            )
            st.session_state.per_page = per_page

        # Fetch documents with pagination parameters
        result = call_api(
            endpoint="action/walker/deepdoc_client_action/list_documents",
            json_data={
                "agent_id": agent_id,
                "page": st.session_state.current_page,
                "per_page": st.session_state.per_page,
                "reporting": True,
            },
            timeout=120,
        )

        if result and result.status_code == 200:
            payload = get_reports_payload(result)
            if payload:
                document_list = []
                if (
                    payload
                    and "items" in payload
                    and isinstance(payload["items"], list)
                ):
                    document_list = payload["items"]

                # Group documents by job_id
                jobs: Dict[str, list] = {}
                for item in document_list:
                    job_id = item["job_id"]
                    if job_id not in jobs:
                        jobs[job_id] = []
                    jobs[job_id].append(item)

                # Pagination controls
                with col3:
                    page_col1, page_col2, page_col3 = st.columns([1, 2, 1])
                    with page_col1:
                        if payload.get("has_previous", False) and st.button("←"):
                            st.session_state.current_page -= 1
                            st.rerun()
                    with page_col2:
                        st.markdown(
                            f"**Page {payload.get('page', 1)}/{payload.get('total_pages', 1)}**"
                        )
                    with page_col3:
                        if payload.get("has_next", False) and st.button("→"):
                            st.session_state.current_page += 1
                            st.rerun()

                # Check if any document is still processing or ingesting
                any_processing = any(
                    item.get("status") in ("PROCESSING", "INGESTING")
                    for item in document_list
                )

                # Display documents grouped by job_id
                for job_id, documents in jobs.items():
                    # Check if any document in this job is still processing
                    job_processing = any(
                        doc.get("status") in ("PROCESSING", "INGESTING")
                        for doc in documents
                    )

                    # Horizontal rule between jobs
                    st.markdown("---")
                    # Right-align the refresh button
                    rcol1, rcol2 = st.columns([1, 11])
                    with rcol1:
                        if job_processing:
                            if st.button("🔄", key=f"refresh_{job_id}"):
                                # Call retrieve_job to manually update status
                                call_api(
                                    endpoint="action/walker/deepdoc_client_action/retrieve_job",
                                    json_data={"agent_id": agent_id, "job_id": job_id},
                                    timeout=120,
                                )
                                st.rerun()
                        else:
                            # a disabled refresh button when not processing
                            st.button("✔️", key=f"done_{job_id}", disabled=True)
                    with rcol2:
                        st.markdown(f"##### Job: {job_id}")

                    # Display job status and dates
                    first_doc = documents[0]
                    status = first_doc.get("status", "").upper()

                    col1, col2, col3 = st.columns([2, 3, 3])
                    with col1:
                        st.markdown(get_status_badge(status), unsafe_allow_html=True)
                    with col2:
                        st.text(
                            f"Created: {format_datetime(first_doc.get('created_on', ''))}"
                        )
                    with col3:
                        if status in ("COMPLETED", "CANCELLED"):
                            st.text(
                                f"Completed: {format_datetime(first_doc.get('completed_on', ''))}"
                            )
                        else:
                            st.text("")  # Empty space for alignment

                    # Handle Cancel Job confirmation flow
                    if job_processing:
                        if (
                            st.session_state.confirm_state["active"]
                            and st.session_state.confirm_state["type"] == "cancel_job"
                            and st.session_state.confirm_state["job_id"] == job_id
                        ):
                            st.warning(
                                f"Are you sure you want to cancel job {job_id}? This action cannot be undone.",
                                icon="⚠️",
                            )
                            col1, col2 = st.columns(2)
                            with col1:
                                if st.button("Yes, Cancel Job"):
                                    # Prepare arguments for cancellation
                                    # Call the cancel_documents walker
                                    cancel_result = call_api(
                                        endpoint="action/walker/deepdoc_client_action/cancel_job",
                                        json_data={
                                            "agent_id": agent_id,
                                            "job_id": job_id,
                                        },
                                        timeout=120,
                                    )
                                    if (
                                        cancel_result
                                        and cancel_result.status_code == 200
                                    ):
                                        st.session_state.current_page = 1
                                        st.session_state.confirm_state = {
                                            "active": False
                                        }
                                        st.rerun()
                                    else:
                                        st.error(f"Failed to cancel job {job_id}.")
                                        st.session_state.confirm_state = {
                                            "active": False
                                        }
                                        st.rerun()
                            with col2:
                                if st.button("No, Keep Job"):
                                    st.session_state.confirm_state = {"active": False}
                                    st.rerun()
                        elif st.button("Cancel Job", key=f"cancel_job_{job_id}"):
                            st.session_state.confirm_state = {
                                "active": True,
                                "type": "cancel_job",
                                "job_id": job_id,
                            }
                            st.rerun()

                    # Handle Delete Job confirmation flow
                    if not job_processing:
                        if (
                            st.session_state.confirm_state["active"]
                            and st.session_state.confirm_state["type"] == "delete_job"
                            and st.session_state.confirm_state["job_id"] == job_id
                        ):
                            st.warning(
                                f"Are you sure you want to delete job {job_id} and all its documents? This action cannot be undone.",
                                icon="⚠️",
                            )
                            col1, col2 = st.columns(2)
                            with col1:
                                if st.button("Yes, Delete Job"):
                                    # Call the delete_documents walker
                                    delete_result = call_api(
                                        endpoint="action/walker/deepdoc_client_action/delete_job",
                                        json_data={
                                            "agent_id": agent_id,
                                            "job_id": job_id,
                                        },
                                        timeout=120,
                                    )
                                    if (
                                        delete_result
                                        and delete_result.status_code == 200
                                    ):
                                        st.session_state.current_page = 1
                                        st.session_state.confirm_state = {
                                            "active": False
                                        }
                                        st.rerun()
                                    else:
                                        st.error(f"Failed to delete job {job_id}.")
                                        st.session_state.confirm_state = {
                                            "active": False
                                        }
                                        st.rerun()
                            with col2:
                                if st.button("No, Keep Job"):
                                    st.session_state.confirm_state = {"active": False}
                                    st.rerun()

                        elif status == "COMPLETED":
                            col1, col2 = st.columns(2)
                            with col1:
                                if st.button("Delete Job", key=f"delete_job_{job_id}"):
                                    st.session_state.confirm_state = {
                                        "active": True,
                                        "type": "delete_job",
                                        "job_id": job_id,
                                    }
                                    st.rerun()
                            with col2:
                                if st.button("View Job", key=f"view_job_{job_id}"):
                                    st.session_state.current_page = 3
                                    st.session_state.job_id_details = job_id
                                    st.session_state.job_details = documents
                                    st.rerun()

                    # Display each document in the job
                    for document in documents:
                        doc_status = document.get("status", "").upper()
                        processing_time = (
                            calculate_processing_time(
                                document.get("created_on"), document.get("completed_on")
                            )
                            if doc_status == "COMPLETED"
                            else ""
                        )

                        col1, col2, col3, col4, col5 = st.columns([3, 3, 2, 2, 2])
                        with col1:
                            # Display document name as a hyperlink if source exists
                            if document.get("source"):
                                st.markdown(
                                    f"[{document['name']}]({document['source']})",
                                    unsafe_allow_html=True,
                                )
                            else:
                                st.text(document["name"])
                        with col2:
                            # Display metadata if available
                            metadata = document.get("metadata", {})
                            if metadata and st.toggle(
                                "Metadata",
                                key=f"metadata_{job_id}_{document['name']}",
                                value=False,
                            ):
                                st.json(metadata)
                        with col3:
                            # Display file type
                            st.text(document.get("mimetype", ""))
                        with col4:
                            # Display processing time if completed
                            if (
                                doc_status == "COMPLETED"
                                and processing_time != "00:00:00"
                            ):
                                st.markdown(f"⏱️ {processing_time}")
                        with col5:
                            # Show "Delete" button if processed, otherwise "Processing"
                            if doc_status in ("COMPLETED", "FAILED", "CANCELLED"):
                                if (
                                    st.session_state.confirm_state["active"]
                                    and st.session_state.confirm_state["type"]
                                    == "delete_doc"
                                    and st.session_state.confirm_state["job_id"]
                                    == job_id
                                    and st.session_state.confirm_state["doc_id"]
                                    == document["id"]
                                ):
                                    col1, col2 = st.columns(2)
                                    with col1:
                                        if st.button(
                                            "✅",
                                            key=f"confirm_delete_{job_id}_{document['id']}",
                                            help="Confirm delete",
                                        ):
                                            # Call the delete_documents walker
                                            delete_result = call_api(
                                                endpoint="action/walker/deepdoc_client_action/delete_documents",
                                                json_data={
                                                    "agent_id": agent_id,
                                                    "documents": [
                                                        {
                                                            "job_id": job_id,
                                                            "doc_id": document["id"],
                                                        }
                                                    ],
                                                },
                                                timeout=120,
                                            )
                                            if delete_result:
                                                st.session_state.confirm_state = {
                                                    "active": False
                                                }
                                                st.rerun()
                                            else:
                                                st.error(
                                                    f"Failed to delete document {document['name']}."
                                                )
                                                st.session_state.confirm_state = {
                                                    "active": False
                                                }
                                                st.rerun()
                                    with col2:
                                        if st.button(
                                            "🚫",
                                            key=f"cancel_delete_{job_id}_{document['id']}",
                                            help="Cancel delete",
                                        ):
                                            st.session_state.confirm_state = {
                                                "active": False
                                            }
                                            st.rerun()
                                # Use a red X icon button for delete
                                elif st.button(
                                    "❌",
                                    key=f"delete_{job_id}_{document['name']}",
                                    help="Delete document",
                                ):
                                    st.session_state.confirm_state = {
                                        "active": True,
                                        "type": "delete_doc",
                                        "job_id": job_id,
                                        "doc_id": document["id"],
                                    }
                                    st.rerun()
                            else:
                                st.text("Processing")

                # Auto-refresh every 5 seconds if any documents are processing
                if any_processing:
                    time.sleep(5)
                    st.rerun()

    if st.session_state.job_id_details:
        st.write("---")
        st.write("## Job Details")

        if "page" not in st.session_state[model_key]:
            st.session_state[model_key]["page"] = 1
        if "per_page" not in st.session_state[model_key]:
            st.session_state[model_key]["per_page"] = 10

        # Items per page selection
        per_page_options = [10, 20, 30, 50, 100]
        new_per_page = st.selectbox(
            "Documents per page:",
            per_page_options,
            index=per_page_options.index(st.session_state[model_key]["per_page"]),
        )

        # Reset page if per_page changes
        if new_per_page != st.session_state[model_key]["per_page"]:
            st.session_state[model_key]["per_page"] = new_per_page
            st.session_state[model_key]["page"] = 1
            st.rerun()

        st.session_state[model_key]["pages_input"] = st.text_input(
            "Enter page numbers (comma or space separated):",
            value="",  # optional default value
            placeholder="e.g., 1,2,3",
        )

        st.session_state[model_key]["pages_input"] = [
            p.strip()
            for p in st.session_state[model_key]["pages_input"]
            .replace(",", " ")
            .split()
            if p.strip().isdigit()
        ]
        st.session_state[model_key][
            "filter_by"
        ] = f'metadata.job_id:="{st.session_state.job_id_details}"'

        if st.session_state[model_key]["pages_input"]:
            st.session_state[model_key][
                "filter_by"
            ] += f' && metadata.page:=[{",".join(st.session_state[model_key]["pages_input"])}]'

        params = {
            "page": st.session_state[model_key].get("page", 1),
            "per_page": st.session_state[model_key].get("per_page", 10),
            "filter_by": st.session_state[model_key]["filter_by"],
            "agent_id": agent_id,
        }

        response = call_api(
            endpoint="action/walker/typesense_vector_store_action/list_documents",
            json_data=params,
        )

        if response and response.status_code == 200:
            result = get_reports_payload(response)
            documents = result.get("documents", [])

            for doc in documents:
                if doc["metadata"].get("title"):
                    title = doc["metadata"]["title"][0].strip()
                else:
                    title = doc["text"]
                    title = title.split("\n")[0].strip()

                title = title[:40]
                page = doc["metadata"].get("page", "N/A")

                with st.expander(f"{title} (Page {page})", expanded=False):
                    if st.session_state.editing_doc_id == doc["id"]:
                        with st.form(key=f"edit_form_{doc['id']}"):
                            new_text = st.text_area(
                                "Text", value=doc["text"], height=200
                            )

                            # Prepare metadata for editing (pretty print JSON)
                            metadata_str = json.dumps(doc["metadata"], indent=2)
                            new_metadata_str = st.text_area(
                                "Metadata (JSON)", value=metadata_str, height=200
                            )

                            c1, c2 = st.columns(2)
                            with c1:
                                if st.form_submit_button("Save"):
                                    try:
                                        new_metadata = json.loads(new_metadata_str)
                                        # Update doc
                                        args = {
                                            "id": doc["id"],
                                            "agent_id": agent_id,
                                            "data": {
                                                "text": new_text,
                                                "metadata": new_metadata,
                                            },
                                        }
                                        result = call_api(
                                            endpoint="action/walker/typesense_vector_store_action/update_document",
                                            json_data=args,
                                        )
                                        if result and result.status_code == 200:
                                            st.success("Document updated!")
                                            st.session_state.editing_doc_id = None
                                            get_reports_payload(result)
                                            st.rerun()
                                        else:
                                            st.error("Failed to update document.")
                                    except json.JSONDecodeError:
                                        st.error("Invalid JSON in metadata.")
                            with c2:
                                if st.form_submit_button("Cancel"):
                                    st.session_state.editing_doc_id = None
                                    st.rerun()
                    else:
                        st.write(doc["text"])
                        st.write("---")

                        col1, col2, col3 = st.columns(
                            [5, 1, 1]
                        )  # first column 5x width of second
                        with col1:
                            st.markdown(f"**Page:** {page}")

                        with col2:
                            # Edit button
                            if st.button("Edit", key=f"edit_btn_{doc['id']}"):
                                st.session_state.editing_doc_id = doc["id"]
                                st.rerun()

                        with col3:
                            # Delete button
                            if st.button("Delete", key=f"delete_{doc['id']}"):
                                args = {"id": doc["id"], "agent_id": agent_id}
                                result = call_api(
                                    endpoint="action/walker/typesense_vector_store_action/delete_document",
                                    json_data=args,
                                )

                                if result and result.status_code == 200:
                                    get_reports_payload(result)
                                    st.rerun()
