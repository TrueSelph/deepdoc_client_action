import logging;
import json;
import yaml;
import from logging { Logger }
import from jivas.agent.core.agent { Agent }
import from jivas.agent.action.action { Action }
import from jivas.agent.action.actions { Actions }
import from jivas.agent.action.agent_graph_walker { agent_graph_walker }
import from jivas.agent.modules.action.path { action_walker_path }


walker import_documents(agent_graph_walker) {
    # action endpoint for listing all documents processed by the deepdoc service
    has with_embeddings:bool = False;
    has data:str = "";
    has purge:bool = False;
    has response:list[dict] = [];
    has reporting:bool = True;

    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    class __specs__ {
        static has private: bool = False;
        static has path: str = action_walker_path(__module__);
        static has excluded: list[str] = ["response"];  # exclude response from the specs
    }

    can on_agent with Agent entry {
        self.logger.info("agent Importing documents from DeepDocClientAction.");
        visit [-->](`?Actions);
    }

    can on_actions with Actions entry {
        visit [-->](`?Action)(?enabled==True)(?label=='DeepDocClientAction');
    }

    can on_action with Action entry {
        self.logger.info("Importing documents from DeepDocClientAction.");
        self.logger.info(f"data: {self.data}");

        if isinstance(self.data, str) {
            try {
                data = json.loads(self.data);
            } except json.JSONDecodeError {
                try {
                    data = yaml.safe_load(self.data);
                } except yaml.YAMLError as e {
                    self.logger.error(f"Invalid data format: {e}");
                    return False;
                }
            }
        } else {
            data = self.data;
        }
        self.response = here.import_documents(data=data, with_embeddings=self.with_embeddings, purge=self.purge);

        if self.reporting {
            report self.response;
        }
    }
}