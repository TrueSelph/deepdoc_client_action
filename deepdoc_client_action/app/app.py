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
            type=["pdf", "docx", "doc", "txt"],
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


# Additional function definitions remain unchanged


# def render_paginated_documents(
#     model_key: str,
#     agent_id: str,
#     module_root: str,
#     documents: list[dict],
#     page: int,
#     per_page: int,
#     total: int,
# ) -> None:
#     """
#     Renders a paginated list of documents.

#     :param model_key: The model key.
#     :param agent_id: The agent ID.
#     :param module_root: The module root.
#     :param documents: The list of documents.
#     :param page: The current page.
#     :param per_page: The number of documents per page.
#     :param total: The total number of documents.
#     """

#     st.divider()
#     st.subheader("Documents")

#     for document in documents:
#         text_preview = document["text"][:200] + (
#             "..." if len(document["text"]) > 100 else ""
#         )

#         # Display edit document form if triggered
#         if st.session_state.get(f"show_edit_document_form_{document['id']}", False):
#             with st.form(f"edit_document_form_{document['id']}"):
#                 edit_document_text = st.text_area(
#                     "Document Text", value=document["text"]
#                 )
#                 submitted = st.form_submit_button("Update")

#                 if submitted:
#                     # Call the function to add the new text document
#                     if call_update_document(
#                         agent_id,
#                         module_root,
#                         id=document["id"],
#                         data={"text": edit_document_text},
#                     ):
#                         st.session_state[
#                             f"show_edit_document_form_{document['id']}"
#                         ] = False
#                         st.rerun()
#                     else:
#                         st.error("Failed to update document")
#         else:
#             st.text(text_preview)

#         # Add buttons for each document
#         col1, col2, col3 = st.columns([1, 1, 10])
#         with col1:
#             if st.button("Edit", key=f"edit_{document['id']}"):
#                 st.session_state[f"show_edit_document_form_{document['id']}"] = True
#                 st.rerun()
#         with col2:
#             if st.button("Delete", key=f"delete_{document['id']}"):
#                 # Call the function to delete the text document
#                 if call_delete_document(agent_id, module_root, id=document["id"]):
#                     st.rerun()
#                 else:
#                     st.error("Failed to delete document")

#     st.divider()

#     # Add a button to add a new document
#     if st.button("Add Document"):
#         # Trigger form visibility in session state
#         st.session_state["show_add_document_form"] = True

#     # Display add document form if triggered
#     if st.session_state.get("show_add_document_form", False):
#         with st.form("add_document_form"):
#             new_document_text = st.text_area("Document Text")
#             submitted = st.form_submit_button("Submit")

#             if submitted:
#                 # Call the function to add the new text document
#                 if call_add_texts(agent_id, module_root, texts=[new_document_text]):
#                     st.session_state["show_add_document_form"] = False
#                     st.rerun()
#                 else:
#                     st.error("Failed to add document")

#     st.divider()

#     if total > 0:

#         # Navigation through pages
#         pages = total // per_page + (1 if total % per_page > 0 else 0)
#         st.write(f"Page {page} of {pages}")

#         if page > 1 and st.button("Previous Page"):
#             st.session_state[model_key]["page"] = page - 1

#         if page < pages and st.button("Next Page"):
#             st.session_state[model_key]["page"] = page + 1


# def call_list_documents(
#     agent_id: str, module_root: str, page: int, per_page: int
# ) -> dict:
#     """
#     Calls the list_documents walker in the Typesense Vector Store Action.

#     :param agent_id: The agent ID.
#     :param module_root: The module root.
#     :param page: The page number.
#     :param per_page: The number of documents per page.
#     :return: The response dictionary.
#     """

#     args = {"page": page, "per_page": per_page}
#     return call_action_walker_exec(agent_id, module_root, "list_documents", args)


# def call_add_texts(agent_id: str, module_root: str, texts: list[str]) -> dict:
#     """
#     Calls the add_texts walker in the Typesense Vector Store Action.

#     :param agent_id: The agent ID.
#     :param module_root: The module root.
#     :param texts: The list of texts to add.
#     :return: The response dictionary.
#     """

#     args = {"texts": texts}
#     return call_action_walker_exec(agent_id, module_root, "add_texts", args)


# def call_delete_document(agent_id: str, module_root: str, id: str) -> dict:
#     """
#     Calls the delete_document walker in the Typesense Vector Store Action.

#     :param agent_id: The agent ID.
#     :param module_root: The module root.
#     :param id: The document ID.
#     :return: The response dictionary.
#     """

#     args = {"id": id}
#     return call_action_walker_exec(agent_id, module_root, "delete_document", args)


# def call_update_document(agent_id: str, module_root: str, id: str, data: dict) -> dict:
#     """
#     Calls the update_document walker in the Typesense Vector Store Action.

#     :param agent_id: The agent ID.
#     :param module_root: The module root.
#     :param id: The document ID.
#     :param data: The data to update.
#     :return: The response dictionary.
#     """

#     args = {"id": id, "data": data}
#     return call_action_walker_exec(agent_id, module_root, "update_document", args)
