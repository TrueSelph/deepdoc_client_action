import logging;
import from logging { Logger }
import from jivas.agent.core.agent { Agent }
import from jivas.agent.action.action { Action }
import from jivas.agent.action.actions { Actions }
import from jivas.agent.action.agent_graph_walker { agent_graph_walker }
import from jivas.agent.modules.action.path { action_walker_path }
import from jac_cloud.plugin.jaseci { JacPlugin as Jac }
import from fastapi { UploadFile }
import asyncio;


walker add_documents(agent_graph_walker) {
    # action endpoint for deepdoc processing and vector_store ingestion

    has files: list[UploadFile] = [];
    has urls:list[str] = [];
    has metadatas:list[dict]=[];
    has from_page:int = 0;
    has to_page:int = 100000;
    has lang:str = "english";
    has with_embeddings:bool = False;  # whether to generate embeddings for the documents
    has response:str = "";
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
        # call the queue_job method on the action

        # check if the urls and files lists are empty
        if( not self.urls and not self.files ) {
            Jac.get_context().status = 400;
            Jac.get_context().error = "No URLs or files provided for processing.";
            self.response = False;
            disengage;
        }

        # generate the callback URL to pass to the deepdoc service
        if( not(callback_url := here.generate_callback_url()) ) {
            Jac.get_context().status = 500;
            Jac.get_context().error = "Unable to complete operation. Failed to generate a callback URL for job scheduling.";
            disengage;
        }

        # iterate through all files and read their content
        if self.files {

            file_list = [];
            loop = asyncio.new_event_loop();
            asyncio.set_event_loop(loop);
            try {
                for i in range(len(self.files)) {
                    file_content = loop.run_until_complete(self.files[i].read());
                    file_list.append({
                        "name": self.files[i].filename,
                        "type": self.files[i].content_type,
                        "content": file_content
                    });
                }
            } except Exception as e {
                self.logger.error(f"Unable to read uploaded files: {str(e)}");
                Jac.get_context().status = 500;
                Jac.get_context().error = "Unable to read uploaded files.";
            } finally {
                loop.close();
            }

            self.response = here.queue_job(
                urls=self.urls,
                files=file_list,
                metadatas=self.metadatas,
                from_page=self.from_page,
                to_page=self.to_page,
                lang=self.lang,
                with_embeddings=self.with_embeddings,
                callback_url=callback_url
            );
        }

        if self.reporting {
            report self.response;
        }
    }

}