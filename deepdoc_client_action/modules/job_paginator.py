class JobPaginator:
    def __init__(self, doc_manifest):
        self.doc_manifest = doc_manifest
        # Store jobs in reverse order while preserving document lists
        self.job_list = list(doc_manifest.items())[::-1]
        self.total_jobs = len(self.job_list)
    
    def _validate_page(self, page:int, total_pages:int) -> int:
        """Ensure page number is within valid range"""
        return max(1, min(page, total_pages))

    def get_page(self, page:int=1, per_page:int=10) -> dict:
        """Retrieve a paginated page of jobs with their documents"""
        total_pages = max(1, (self.total_jobs + per_page - 1) // per_page)
        validated_page = self._validate_page(page, total_pages)
        
        start_index = (validated_page - 1) * per_page
        end_index = start_index + per_page
        
        current_jobs = self.job_list[start_index:end_index]
        
        return {
            "items": [{
                "job_id": job_id,
                "documents": documents
            } for job_id, documents in current_jobs],
            "pagination": {
                "current_page": validated_page,
                "per_page": per_page,
                "total_jobs": self.total_jobs,
                "total_pages": total_pages,
                "has_previous": validated_page > 1,
                "has_next": validated_page < total_pages,
                "previous_page": validated_page - 1 if validated_page > 1 else None,
                "next_page": validated_page + 1 if validated_page < total_pages else None,
            }
        }