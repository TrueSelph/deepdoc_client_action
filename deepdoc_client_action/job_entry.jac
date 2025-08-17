import from datetime { datetime, timezone }
import from jivas.agent.core.graph_node { GraphNode }
import from actions.jivas.deepdoc_client_action.doc_entry { DocEntry }
import from actions.jivas.deepdoc_client_action.doc_file_entry { DocFileEntry }
import from actions.jivas.deepdoc_client_action.doc_url_entry { DocURLEntry }
import from actions.jivas.deepdoc_client_action.item_status { ItemStatus }
import from jivas.agent.modules.system.common { node_obj }
import from jac_cloud.plugin.jaseci { JacPlugin as Jac }


node JobEntry(GraphNode) {
    # represents a deepdoc job
    has collection_id:str = "";
    has job_id:str = "";
    has status:ItemStatus = ItemStatus.PENDING;
    has created_on:str = str((datetime.now(timezone.utc)).isoformat());
    has completed_on:str = "";
    has messages:list = [];

    def get_status() -> ItemStatus {
        return self.status;
    }

    def set_status(status:ItemStatus) -> None {
        # timestamp completed on
        if status in [ItemStatus.COMPLETED, ItemStatus.FAILED, ItemStatus.CANCELLED] {
            self.completed_on = str((datetime.now(timezone.utc)).isoformat());
        }
        self.status = status;
    }

    def add_message(message:str) -> None {
        self.messages.append(message);
    }

    def get_job_id() -> str {
        return self.job_id;
    }

    def set_job_id(job_id:str) -> None {
        self.job_id = job_id;
    }

    def add_doc_url_entry(url:str, metadata:dict={}) -> DocEntry {
        # adds a doc url entry to this job entry

        if not url {
            return None;
        }

        # TODO: Check for duplicates

        doc_url_entry = DocURLEntry(
            collection_id = self.collection_id,
            job_id = self.job_id,
            status = ItemStatus.PENDING if not self.job_id else ItemStatus.PROCESSING,
            name = url.split("/")[-1],
            source = url,
            metadata = metadata
        );
        # now we attach it to the job
        self ++> doc_url_entry;

        return doc_url_entry;
    }

    def add_doc_file_entry(name:str, source:str, mimetype:str="", metadata:dict={}) -> DocEntry {
        # adds a doc url entry to this job entry

        if not name {
            return None;
        }

        # TODO: Check for duplicates

        doc_file_entry = DocFileEntry(
            collection_id = self.collection_id,
            job_id = self.job_id,
            status = ItemStatus.PENDING if not self.job_id else ItemStatus.PROCESSING,
            name = name,
            source = source,
            mimetype = mimetype,
            metadata = metadata
        );
        # now we attach it to the job
        self ++> doc_file_entry;

        return doc_file_entry;
    }

    def get_doc_entries() -> list {
        # retrieves a list of doc entries
        return [-->](`?DocEntry);
    }

    def get_doc_entry(id:str) -> DocEntry {
        # retrieves an attached document entry by id
        return node_obj([-->](`?DocEntry)(?id == id));
    }

    def get_doc_entry_by_name(name:str) -> DocEntry {
        # retrieves an attached document entry by id
        return node_obj([-->](`?DocEntry)(?name == name));
    }

    def delete_doc_entry(id:str) -> bool {
        # removes an attached document entry by id
        doc_entry = node_obj([-->](`?DocEntry)(?id == id));
        if not doc_entry {
            return False;
        }
        Jac.destroy( doc_entry );
        # if this is the last entry in this job, also remove the job itself
        if not [-->](`?DocEntry) {
            self.delete();
        }
        return True;
    }

    def delete() -> list {
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