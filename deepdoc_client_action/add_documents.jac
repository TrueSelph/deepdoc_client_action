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
    has metadatas:list[dict]=[];
    has from_page:int = 0;
    has to_page:int = 100000;
    has lang:str = "english";
    has response:str = "";

    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    can on_agent with Agent entry {
        visit [-->](`?Actions);
    }

    can on_actions with Actions entry {
        visit [-->](`?Action)(?enabled==True)(?label=='DeepDocClientAction');
    }

    can on_action with Action entry {
        # call the queue_job method on the action

        # check if the urls and files lists are empty
        if( not self.urls and not self.files ) {
            Jac.get_context().status = 400;
            Jac.get_context().error = "No URLs or files provided for processing.";
            self.response = False;
            disengage;
        }

        # generate the callback URL to pass to the deepdoc service
        if( not(callback_url := here.generate_callback_url("deepdoc_callback")) ) {
            Jac.get_context().status = 500;
            Jac.get_context().error = "Unable to complete operation. Failed to generate a callback URL for job scheduling.";
            disengage;
        }

        self.response = here.queue_job(
            urls=self.urls,
            files=self.files,
            metadatas=self.metadatas,
            from_page=self.from_page,
            to_page=self.to_page,
            lang=self.lang,
            callback_url=callback_url
        );
    }

}