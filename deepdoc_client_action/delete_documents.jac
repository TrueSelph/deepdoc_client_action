import logging;
import from logging { Logger }
import from jivas.agent.core.agent { Agent }
import from jivas.agent.action.action { Action }
import from jivas.agent.action.actions { Actions }
import from jivas.agent.action.agent_graph_walker { agent_graph_walker }
import from jac_cloud.plugin.jaseci { JacPlugin as Jac }
import from jivas.agent.modules.action.path { action_walker_path }


walker delete_documents(agent_graph_walker) {
    # action endpoint which removes documents from the vector store and deletes the local file system entries

    # a list of {job_id, filename} pairs for removal
    has documents:list[dict] = [];
    has response:bool = False;
    has reporting:bool = True;

    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    class __specs__ {
        static has private: bool = False;
        static has path: str = action_walker_path(__module__);
        static has excluded: list[str] = ["response"];  # exclude response from the specs
    }

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
                doc.get("doc_id", "")
            ) {
                success = False;
                break;
            }
        }

        self.response = success;
        # set the response status
        Jac.get_context().status = 200;

        if self.reporting {
            report self.response;
        }
    }

}