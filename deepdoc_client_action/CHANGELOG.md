# 0.0.1
- Initialized package using jvcli

# 0.0.2
- Added file serving of uploaded documents and document management which links to vector store content. Deleting a processed document will also remove all of its references from the vector store.

# 0.0.3
- Updated action to update descriptor export on doc_manifest update
- Updated action to allow custom metadata to be added to each document ingested

# 0.0.4
- Patched file_path bug in action
- Updated docs to include API docs

# 0.0.5
- Catered for spaces in document filenames which affect the rendering of URLs

# 0.0.6
- Updated doc list to group docs by job and auto-refresh upon completion of job

# 0.0.7
- Added document URL support
- Added pagination for document list by job
- Modified list_documents to respond t an 'all' flag which returns all docs

# 0.0.8
- Refactored to store doc_manifest in memory collection

# 0.0.9
- Bugfix: page numbers not represented accurately on ingested chunks
- Bugfix: migration now uses file interface for retrieving old file contents

# 0.0.10
- Bugfix: fixed generation of new shortened url for each ingested chunk
- Bugfix: added safeguard against creating multiple job entries with same job_id

# 0.0.11
- Updated for compatibility with JIVAS alpha.51 which introduces add_texts_with_embeddings under VectorStoreAction

# 0.0.12
- Added tracked doc count for more optimal paging

# 0.0.13
- Removed enumeration of job entries for list_documents to improve paging response

# 0.1.0
- Updated to support Jivas 2.1.0