import logging;
import from logging { Logger }
import from jivas.agent.core.agent { Agent }
import from jivas.agent.action.action { Action }
import from jivas.agent.action.actions { Actions }
import from jivas.agent.action.interact_graph_walker { interact_graph_walker }
import from jac_cloud.plugin.jaseci { JacPlugin as Jac }


walker delete_job(interact_graph_walker) {
    # action endpoint which removes documents from the vector store and deletes the local file system entries

    # a list of {job_id, filename} pairs for removal
    has job_id:str = "";
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

        # remove the document
        self.response = here.delete_job_entry(self.job_id);

        if not self.response {
            Jac.get_context().status = 400;
            Jac.get_context().error = "Failed to delete the job.";
            self.response = False;
        }

    }

}