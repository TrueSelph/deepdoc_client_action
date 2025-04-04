import:py logging;
import:py traceback;
import:py from logging { Logger }
import:jac from jivas.agent.core.agent { Agent }
import:jac from jivas.agent.action.action { Action }
import:jac from jivas.agent.action.actions { Actions }
import:jac from jivas.agent.action.interact_graph_walker { interact_graph_walker }


walker deepdoc_callback :interact_graph_walker: {
    # action endpoint for handling the deepdoc callback routine which processes deepdoc job and ingests into vector_store

    has job_id:str = "";
    has status:str = "";
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
        # processes deepdoc job data and ingests into vector_store
        if(self.job_id == "completed") {
            # first get the deepdoc job data
            job_data = here.get_deepdoc_job(job_id=self.job_id);
            # now ingest the job data into the vector store
            self.response = here.ingest_deepdoc_job(job_data=job_data);
        }

    }

}