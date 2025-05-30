import:jac from jivas.agent.core.graph_node { GraphNode }

node DocEntry :GraphNode: {
    # represents a base deepdoc job document entry
    has name:str = "";
    has source:str = "";
    has mimetype:str = "";
    has metadata:dict = {};
    has chunk_ids:list = [];

    can get_job() {
        Utils.node_obj([<--]);
    }
    
    can get_name() -> str {
        """Returns the name of the document."""
        return self.name;
    }

    can set_name(name:str) -> None {
        """Sets the name of the document."""
        self.name = name;
    }

    can get_source() -> str {
        """Returns the source of the document."""
        return self.source;
    }

    can set_source(source:str) -> None {
        """Sets the source of the document."""
        self.source = source;
    }

    can get_metadata() -> dict {
        """Returns the metadata associated with the document."""
        return self.metadata;
    }

    can set_metadata(metadata:dict) -> None {
        """Sets the metadata for the document."""
        self.metadata = metadata;
    }

    can add_metadata(key:str, value:any) -> None {
        """Adds or updates a key-value pair in the document's metadata."""
        self.metadata[key] = value;
    }

    can set_mimetype(mimetype:str) -> None {
        """Sets the mimetype of the document."""
        self.name = name;
    }

    can get_mimetype() -> str {
        """Returns the mimetype of the document."""
        return self.mimetype;
    }

    can get_chunk_ids() -> list {
        """Returns the list of chunk IDs for the document."""
        return self.chunk_ids;
    }

    can set_chunk_ids(chunk_ids:list) -> None {
        """Sets the list of chunk IDs for the document."""
        self.chunk_ids = chunk_ids;
    }

    can add_chunk_id(chunk_id:any) -> None {
        """Appends a chunk ID to the document's chunk ID list."""
        self.chunk_ids.append(chunk_id);
    }
}