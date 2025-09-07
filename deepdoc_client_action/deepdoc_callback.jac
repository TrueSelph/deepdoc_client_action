import logging;
import traceback;
import from logging { Logger }
import from jivas.agent.core.agent { Agent }
import from jivas.agent.action.action { Action }
import from jivas.agent.action.actions { Actions }
import from jivas.agent.action.action_webhook_walker { action_webhook_walker }
import from jivas.agent.modules.action.path { action_webhook_path }
import from actions.jivas.deepdoc_client_action.item_status { ItemStatus }
import from jac_cloud.plugin.jaseci { JacPlugin as Jac }


walker deepdoc_callback(action_webhook_walker) {
    # action endpoint for handling the deepdoc callback routine which processes deepdoc job and ingests into vector_store

    has job_id:str = "";  # job ID from the deepdoc service
    has status:str = "";  # status of the job (e.g., "completed", "failed")
    has error:str = "";  # error message if the job failed
    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    # set up walker as webhook
    class __specs__(action_webhook_walker.__specs__) {
        static has private: bool = False; # make it public
        static has path: str = action_webhook_path(__module__);
    }

    can on_agent with Agent entry {
        # grab payload from webhook call
        payload = self.get_request_json();

        if payload {
            self.job_id = payload.get("job_id", "");
            self.status = payload.get("status", "");
            self.error = payload.get("error", "");
        }

        # handle request here to ensure it's worth the walk
        if(not self.job_id or not self.status) {
            self.response = {
                "status": 401,
                "message": "No payload received"
            };
            disengage;
        }

        visit [-->](`?Actions);
    }

    can on_actions with Actions entry {
        visit [-->](`?Action)(?enabled==True)(?label=='DeepDocClientAction');
    }

    can on_action with Action entry {
        # Process deepdoc job data and ingest into vector_store
        self.response = self.retrieve_job(job_id=self.job_id);
    }

}