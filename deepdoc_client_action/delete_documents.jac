import:py logging;
import:py traceback;
import:py from logging { Logger }
import:jac from jivas.agent.core.agent { Agent }
import:jac from jivas.agent.action.action { Action }
import:jac from jivas.agent.action.actions { Actions }
import:jac from jivas.agent.action.interact_graph_walker { interact_graph_walker }


walker delete_documents :interact_graph_walker: {
    # action endpoint which removes documents from the vector store and deletes the local file system entries

    # a list of {job_id, filename} pairs for removal
    has documents:list[dict] = [];
    has response:bool = False;

    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    can on_agent with Agent entry {
        visit [-->](`?Actions);
    }

    can on_actions with Actions entry {
        visit [-->](`?Action)(?enabled==True)(?label=='DeepDocClientAction');
    }

    can on_action with Action entry {
        # call the remove/delete method on the action

        success = True;

        # check if the documents list is empty
        if not self.documents {
            Jac.get_context().status = 400;
            Jac.get_context().error = "No documents provided for removal.";
            self.response = False;
            disengage;
        }

        for doc in self.documents {
            # check if the document is a valid dict
            if not isinstance(doc, dict) {
                Jac.get_context().status = 400;
                Jac.get_context().error = "Invalid document format. Expected a dictionary.";
                success = False;
                continue;
            }

            # remove the document
            if not here.delete_doc_entry(
                doc.get("job_id", ""),
                doc.get("filename", "")
            ) {
                success = False;
                break;
            }
        }

        self.response = success;
        # set the response status
        Jac.get_context().status = 200;
    }

}