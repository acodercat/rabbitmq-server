-module(rabbitmq_prelaunch_helpers).

-export([mkdir_p/1,
         get_env/1,
         set_env/2]).

mkdir_p(Path) ->
    [Root | Components] = filename:split(Path),
    mkdir_p(Root, Components).

mkdir_p(Parent, [Component | Rest]) ->
    Dir = filename:join(Parent, Component),
    case file:make_dir(Dir) of
        ok              -> mkdir_p(Dir, Rest);
        {error, eexist} -> mkdir_p(Dir, Rest);
        Error           -> Error
    end;
mkdir_p(_, []) ->
    ok.

get_env(Key) ->
    application:get_env(rabbitmq_prelaunch, Key).

set_env(Key, Value) ->
    ok = application:set_env(rabbitmq_prelaunch, Key, Value).
