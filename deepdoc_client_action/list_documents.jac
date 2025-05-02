import:py logging;
import:py traceback;
import:py from logging { Logger }
import:jac from jivas.agent.core.agent { Agent }
import:jac from jivas.agent.action.action { Action }
import:jac from jivas.agent.action.actions { Actions }
import:jac from jivas.agent.action.interact_graph_walker { interact_graph_walker }
import:py from .modules.job_paginator { JobPaginator }


walker list_documents :interact_graph_walker: {
    # action endpoint for listing all documents processed by the deepdoc service

    has page:int = 1;
    has per_page:int = 10;
    has response:list[dict] = [];

    # set up logger
    static has logger:Logger = logging.getLogger(__name__);

    can on_agent with Agent entry {
        visit [-->](`?Actions);
    }

    can on_actions with Actions entry {
        visit [-->](`?Action)(?enabled==True)(?label=='DeepDocClientAction');
    }

    can on_action with Action entry {
        # get the paged list of documents from the manifest
        paginator = JobPaginator(here.doc_manifest);
        self.response = paginator.get_page(page=self.page, per_page=self.per_page);
    }

}