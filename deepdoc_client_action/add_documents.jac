import:py logging;
import:py traceback;
import:py from logging { Logger }
import:jac from jivas.agent.core.agent { Agent }
import:jac from jivas.agent.action.action { Action }
import:jac from jivas.agent.action.actions { Actions }
import:jac from jivas.agent.action.interact_graph_walker { interact_graph_walker }


walker add_documents :interact_graph_walker: {
    # action endpoint for deepdoc processing and vector_store ingestion

    has urls:list[str] = [];
    has files:list[dict] = [];
    has from_page:int = 0;
    has to_page:int = 100000;
    has lang:str = "english";
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
        # call the queue_deepdoc_job method on the action

        # generate the callback URL to pass to the deepdoc service
        if( not(callback_url := here.get_callback_url("deepdoc_callback")) ) {
            Jac.get_context().status = 500;
            Jac.get_context().error = "Unable to complete operation. Failed to generate a callback URL for job scheduling.";
            disengage;
        }

        # Convert files to a collection of bytestreams if provided
        processed_files = [
            file['content'] for file in self.files if 'content' in file
        ] if self.files else [];
        

        self.response = here.queue_deepdoc_job(
            urls=self.urls,
            files=processed_files,
            from_page=self.from_page,
            to_page=self.to_page,
            lang=self.lang,
            callback_url=callback_url
        );

        # set the response status
        Jac.get_context().status = 200;
    }

}