import:py logging;
import:py traceback;
import:py from logging { Logger }
import:jac from jivas.agent.core.agent { Agent }
import:jac from jivas.agent.action.action { Action }
import:jac from jivas.agent.action.actions { Actions }
import:jac from jivas.agent.action.interact_graph_walker { interact_graph_walker }


walker deepdoc_callback :interact_graph_walker: {
    # action endpoint for handling the deepdoc callback routine which processes deepdoc job and ingests into vector_store

    # beacuse this is a callback/webhook, we have to use the following params
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

        # quietly ignore cancelled jobs
        if job_id in here.cancelled_jobs {
            here.cancelled_jobs.remove(job_id);
            return None;
        }

        if status == "completed" {
            # Retrieve the deepdoc job data
            job_data = here.get_deepdoc_job(job_id=job_id);

            if job_id and job_data {
                try {
                    # Ingest the job data into the vector store
                    self.response = here.ingest_deepdoc_job(job_id=job_id, job_data=job_data);
                } except Exception as e {
                    self.logger.error(f"Error during ingestion: {str(e)}");
                    self.response = False;
                }
            } else {
                self.logger.error("DeepDoc job data is incomplete or missing");
                here.delete_doc_manifest_job(job_id=job_id);
                self.response = False;
            }
        } else {
            self.logger.error(f"DeepDoc job failed with status: {status} - {error_message}");
            here.delete_doc_manifest_job(job_id=job_id);
            self.response = False;
        }
    }

}