import:py logging;
import:py traceback;
import:py from logging { Logger }
import:jac from jivas.agent.core.agent { Agent }
import:jac from jivas.agent.action.action { Action }
import:jac from jivas.agent.action.actions { Actions }
import:jac from jivas.agent.action.interact_graph_walker { interact_graph_walker }


walker cancel_job :interact_graph_walker: {
    # action endpoint which cancels document jobs and removes document from the manifest and deletes the local file system entries

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

        success = True;

        # check if the documents list is empty
        if not self.job_id {
            Jac.get_context().status = 400;
            Jac.get_context().error = "No Job ID provided for cancellation.";
            self.response = False;
            disengage;
        }

        self.response = here.cancel_job(job_id=self.job_id);
        if not self.response {
            Jac.get_context().status = 500;
            Jac.get_context().error = "Failed to cancel the job.";
            success = False;
        }
        # set the response status
        Jac.get_context().status = 200;
    }

}