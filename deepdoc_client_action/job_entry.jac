import:py from datetime { datetime, timezone }
import:jac from jivas.agent.core.graph_node { GraphNode }
import:jac from actions.jivas.deepdoc_client_action.doc_entry { DocEntry }
import:jac from actions.jivas.deepdoc_client_action.doc_file_entry { DocFileEntry }
import:jac from actions.jivas.deepdoc_client_action.doc_url_entry { DocURLEntry }
import:jac from actions.jivas.deepdoc_client_action.item_status { ItemStatus }
import:py from jivas.agent.modules.agentlib.utils { Utils }

node JobEntry :GraphNode: {
    # represents a deepdoc job
    has job_id:str = "";
    has status:ItemStatus = ItemStatus.PENDING;
    has created_on:str = str((datetime.now(timezone.utc)).isoformat());
    has completed_on:str = "";
    has messages:list = [];

    can get_status() -> ItemStatus {
        return self.status;
    }

    can set_status(status:ItemStatus) -> None {
        # timestamp completed on
        if status in [ItemStatus.COMPLETED, ItemStatus.FAILED, ItemStatus.CANCELLED] {
            self.completed_on = str((datetime.now(timezone.utc)).isoformat());
        }
        self.status = status;
    }

    can add_message(message:str) -> None {
        self.messages.append(message);
    }

    can get_job_id() -> str {
        return self.job_id;
    }

    can set_job_id(job_id:str) -> None {
        self.job_id = job_id;
    }

    can add_doc_url_entry(url:str, metadata:dict={}) -> DocEntry {
        # adds a doc url entry to this job entry

        if not url {
            return None;
        }

        # TODO: Check for duplicates

        doc_url_entry = DocURLEntry(
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

    can add_doc_file_entry(name:str, source:str, mimetype:str="", metadata:dict={}) -> DocEntry {
        # adds a doc url entry to this job entry

        if not name {
            return None;
        }

        # TODO: Check for duplicates

        doc_file_entry = DocFileEntry(
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

    can get_doc_entries() -> list {
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

    can delete_doc_entry(id:str) -> bool {
        # removes an attached document entry by id
        doc_entry = Utils.node_obj([-->](`?DocEntry)(?id == id));
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

    can delete() -> list {
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