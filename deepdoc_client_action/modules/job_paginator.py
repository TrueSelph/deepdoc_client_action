"""Module for paginating through document processing jobs with their associated documents.

This module provides the JobPaginator class which handles pagination of document processing jobs,
allowing for efficient retrieval of jobs in pages with their associated document lists.
"""

from typing import Any, Dict


class JobPaginator:
    """Paginates through document processing jobs with their associated documents.

    Attributes:
        doc_manifest: A dictionary mapping job IDs to their document lists.
        job_list: List of jobs in reverse order while preserving document lists.
        total_jobs: Total number of jobs available.
    """

    def __init__(self, doc_manifest: Dict[str, Any]) -> None:
        """Initialize the JobPaginator with a document manifest.

        Args:
            doc_manifest: A dictionary mapping job IDs to their document lists.
        """
        self.doc_manifest = doc_manifest
        # Store jobs in reverse order while preserving document lists
        self.job_list = list(doc_manifest.items())[::-1]
        self.total_jobs = len(self.job_list)

    def _validate_page(self, page: int, total_pages: int) -> int:
        """Ensure page number is within valid range.

        Args:
            page: Requested page number.
            total_pages: Total number of available pages.

        Returns:
            Validated page number within the correct range.
        """
        return max(1, min(page, total_pages))

    def get_page(self, page: int = 1, per_page: int = 10) -> dict:
        """Retrieve a paginated page of jobs with their documents.

        Args:
            page: Page number to retrieve (default: 1).
            per_page: Number of jobs per page (default: 10).

        Returns:
            A dictionary containing:
                - items: List of job dictionaries with job_id and documents
                - pagination: Metadata about the current pagination state
        """
        total_pages = max(1, (self.total_jobs + per_page - 1) // per_page)
        validated_page = self._validate_page(page, total_pages)

        start_index = (validated_page - 1) * per_page
        end_index = start_index + per_page

        current_jobs = self.job_list[start_index:end_index]

        return {
            "items": [
                {"job_id": job_id, "documents": documents}
                for job_id, documents in current_jobs
            ],
            "pagination": {
                "current_page": validated_page,
                "per_page": per_page,
                "total_jobs": self.total_jobs,
                "total_pages": total_pages,
                "has_previous": validated_page > 1,
                "has_next": validated_page < total_pages,
                "previous_page": validated_page - 1 if validated_page > 1 else None,
                "next_page": (
                    validated_page + 1 if validated_page < total_pages else None
                ),
            },
        }
