import:py from datetime { datetime, timezone }
import:jac from jivas.agent.core.graph_node { GraphNode }
import:jac from actions.jivas.deepdoc_client_action.item_status { ItemStatus }
import:py from jivas.agent.modules.agentlib.utils { Utils }

node DocEntry :GraphNode: {
    # represents a base deepdoc job document entry
    has job_id:str = "";
    has status:ItemStatus = ItemStatus.PENDING;
    has created_on:str = str((datetime.now(timezone.utc)).isoformat());
    has completed_on:str = "";
    has name:str = "";
    has source:str = "";
    has mimetype:str = "";
    has metadata:dict = {};
    has chunk_ids:list = [];

    can get_job() {
        Utils.node_obj([<--]);
    }

    can get_status() -> ItemStatus {
        # Returns the status of the document. #
        return self.status;
    }

    can set_status(status:ItemStatus) -> None {
        # timestamp completed on
        if status in [ItemStatus.COMPLETED, ItemStatus.FAILED, ItemStatus.CANCELLED] {
            self.completed_on = str((datetime.now(timezone.utc)).isoformat());
        }
        self.status = status;
    }

    can get_name() -> str {
        # Returns the name of the document. #
        return self.name;
    }

    can set_name(name:str) -> None {
        # Sets the name of the document. #
        self.name = name;
    }

    can get_source() -> str {
        # Returns the source of the document.#
        return self.source;
    }

    can set_source(source:str) -> None {
        # Sets the source of the document.#
        self.source = source;
    }

    can get_metadata() -> dict {
        # Returns the metadata associated with the document.#
        return self.metadata;
    }

    can set_metadata(metadata:dict) -> None {
        # Sets the metadata for the document.#
        self.metadata = metadata;
    }

    can add_metadata(key:str, value:any) -> None {
        # Adds or updates a key-value pair in the document's metadata.#
        self.metadata[key] = value;
    }

    can set_mimetype(mimetype:str) -> None {
        # Sets the mimetype of the document.#
        self.name = name;
    }

    can get_mimetype() -> str {
        # Returns the mimetype of the document.#
        return self.mimetype;
    }

    can get_chunk_ids() -> list {
        # Returns the list of chunk IDs for the document.#
        return self.chunk_ids;
    }

    can set_chunk_ids(chunk_ids:list) -> None {
        # Sets the list of chunk IDs for the document.#
        self.chunk_ids = chunk_ids;
    }

    can add_chunk_id(chunk_id:any) -> None {
        # Appends a chunk ID to the document's chunk ID list.#
        self.chunk_ids.append(chunk_id);
    }
}