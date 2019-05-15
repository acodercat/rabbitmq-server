-module(rabbitmq_prelaunch_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Prelaunch = #{id => prelaunch,
                  start => {rabbitmq_prelaunch_worker,
                            start_link,
                            []},
                  restart => transient},
    Procs = [Prelaunch],
    {ok, {{one_for_one, 1, 5}, Procs}}.
