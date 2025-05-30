import from enum { unique }
import:jac from jivas.agent.core.graph_node { GraphNode }
import:jac from actions.jivas.deepdoc_client_action.doc_entry { DocEntry }
import:jac from actions.jivas.deepdoc_client_action.doc_file_entry { DocFileEntry }
import:jac from actions.jivas.deepdoc_client_action.doc_url_entry { DocURLEntry }

@unique
enum JobStatus {
    PENDING = 'PENDING', # job is being created, no job ID from deepdoc server yet
    PROCESSING = 'PROCESSING', # job is currently being processed
    INGESTING = 'INGESTING', # received doc chunks..currently being ingested
    CANCELLED = 'CANCELLED', # job is cancelled
    FAILED = 'FAILED', # job failed to complete
}

node JobEntry :GraphNode: {
    # represents a deepdoc job
    has job_id:str = "";
    has status:JobStatus = JobStatus.PENDING;

    can get_status() -> JobStatus {
        return self.status;
    }

    can set_status(status:JobStatus) -> None {
        return self.status = status;
    }

    can get_job_id() -> str {
        return self.job_id;
    }

    can set_job_id(job_id:str) -> None {
        return self.job_id = job_id;
    }

    can add_doc_url_entry(url:str, metadata:dict={}) -> DocEntry {
        # adds a doc url entry to this job entry

        if not url {
            return None;
        }

        # TODO: Check for duplicates
        
        doc_url_entry = DocURLEntry(
            name = url.split("/")[-1],
            source = url,
            metadata = metadata
        );
        # now we attach it to the job
        self ++> doc_url_entry;

        return doc_url_entry;
    }

    can add_doc_file_entry(name:str, source:str, mimetype:str="", metadata:dict={}) -> DocEntry {
        # adds a doc url entry to this job entry

        if not name {
            return None;
        }

        # TODO: Check for duplicates
        
        doc_file_entry = DocFileEntry(
            name = name,
            source = source,
            mimetype = mimetype,
            metadata = metadata
        );
        # now we attach it to the job
        self ++> doc_file_entry;

        return doc_file_entry;
    }

    can list_doc_entries() -> list {
        # retrieves a list of doc entries
        return [-->](`?DocEntry);
    }

    can get_doc_entry(id:str) -> DocEntry {
        # retrieves an attached document entry by id
        return Utils.node_obj([-->](`?DocEntry)(?id == id));
    }

    can get_doc_entry_by_name(name:str) -> DocEntry {
        # retrieves an attached document entry by id
        return Utils.node_obj([-->](`?DocEntry)(?name == name));
    }

    can delete_doc_entry(id:str) {
        # removes an attached document entry by id
        Jac.destroy( [-->](`?DocEntry)(?id == id) );
        # if this is the last entry in this job, also remove the job itself
        if not [-->](`?DocEntry) {
            self.delete_job();
        }
    }

    can delete_job() -> list {
        return (self spawn _purge_job()).removed;
    }

}

walker _purge_job {
    # walker which carries out the traversal and purging of jobs and any related docs

    has removed:list = [];

    obj __specs__ {
        # make this a private walker
        static has private: bool = True;
    }

    can on_job with JobEntry entry {
        visit [-->];
        self.removed.append(here);
        Jac.destroy(here);
    }

    can on_doc_entry with DocEntry entry {
        self.removed.append(here);
        Jac.destroy(here);
    }
}