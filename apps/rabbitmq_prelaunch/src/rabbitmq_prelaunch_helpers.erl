-module(rabbitmq_prelaunch_helpers).

-export([mkdir_p/1,
         is_dev_environment/0,
         exit/1]).

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

is_dev_environment() ->
    case file:get_cwd() of
        {ok, Cwd} ->
            FileToCheck = filename:join(Cwd, "erlang.mk"),
            filelib:is_regular(FileToCheck);
        _ ->
            false
    end.

exit(Reason) when is_atom(Reason) ->
    init:stop(reason_to_sysexit(Reason));
exit(Status) when is_integer(Status) ->
    init:stop(Status).

reason_to_sysexit(ex_usage)     -> 64;
reason_to_sysexit(ex_dataerr)   -> 65;
reason_to_sysexit(ex_software)  -> 70;
reason_to_sysexit(ex_cantcreat) -> 73;
reason_to_sysexit(ex_config)    -> 78.
