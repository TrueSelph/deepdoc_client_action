## 0.0.1
- Initialized package using jvcli

## 0.0.2
- Added file serving of uploaded documents and document management which links to vector store content. Deleting a processed document will also remove all of its references from the vector store.

## 0.0.3
- Updated action to update descriptor export on doc_manifest update
- Updated action to allow custom metadata to be added to each document ingested

## 0.0.4
- Patched file_path bug in action
- Updated docs to include API docs

## 0.0.5
- Catered for spaces in document filenames which affect the rendering of URLs

## 0.0.6
- Updated doc list to group docs by job and auto-refresh upon completion of job

## 0.0.7
- Added document URL support