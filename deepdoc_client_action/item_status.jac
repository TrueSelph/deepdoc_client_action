import from enum { unique }

@unique
enum ItemStatus {
    PENDING = 'PENDING', # job is being created, no job ID from deepdoc server yet
    PROCESSING = 'PROCESSING', # job is currently being processed
    INGESTING = 'INGESTING', # received doc chunks..currently being ingested
    COMPLETED = 'COMPLETED', # set when job is fully ingested
    CANCELLED = 'CANCELLED', # job is cancelled
    FAILED = 'FAILED', # job failed to complete
}