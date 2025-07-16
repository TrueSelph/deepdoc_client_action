import logging;
import traceback;
import from logging { Logger }
import from jivas.agent.core.agent { Agent }
import from jivas.agent.action.action { Action }
import from jivas.agent.action.actions { Actions }
import from jivas.agent.action.agent_graph_walker { agent_graph_walker }
import from jac_cloud.plugin.jaseci { JacPlugin as Jac }


walker deepdoc_callback(agent_graph_walker) {
    # action endpoint for handling the deepdoc callback routine which processes deepdoc job and ingests into vector_store

    # because this is a callback/webhook, we have to use the following params
    has headers:dict = {};
    # main param for incoming webhook data
    has params:dict = {};
    # main param for outgoing webhook data
    has response:bool = False;

    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    can on_agent with Agent entry {

        # handle request here to ensure it's worth the walk
        if(not self.params) {
            Jac.get_context().status = 200;
            disengage;
        }

        visit [-->](`?Actions);
    }

    can on_actions with Actions entry {
        visit [-->](`?Action)(?enabled==True)(?label=='DeepDocClientAction');
    }

    can on_action with Action entry {
        # Process deepdoc job data and ingest into vector_store

        job_id = self.params.get("job_id", "");
        status = self.params.get("status", "");
        error_message = self.params.get("error", "");

        if status == "completed" {
            # Retrieve the deepdoc job data
            job_data = here.get_job_status(job_id=job_id);

            if job_id and job_data {
                try {
                    # Ingest the job data into the vector store
                    self.response = here.ingest_job(job_id=job_id, job_data=job_data);
                } except Exception as e {
                    self.logger.error(f"Error during ingestion: {str(e)}");
                    self.logger.error(traceback.format_exc());
                    self.response = False;
                }
            } else {
                self.logger.error("DeepDoc job data is incomplete or missing");
                here.delete_job_entry(job_id=job_id);
                self.response = False;
            }
        } else {
            self.logger.error(f"DeepDoc job failed with status: {status} - {error_message}");
            here.delete_job_entry(job_id=job_id);
            self.response = False;
        }
    }

}