-module(rabbitmq_prelaunch_helpers).

-export([get_env_var/1,
         get_env_var/2,
         get_prefixed_env_var/1,
         get_prefixed_env_var/2,
         normalize_path/1,
         mkdir_p/1,
         is_dev_environment/0,
         exit/1]).

get_env_var(VarName) ->
    case os:getenv(VarName) of
        false -> false;
        ""    -> false;
        Value -> Value
    end.

get_env_var(VarName, DefaultValue) ->
    case get_env_var(VarName) of
        false -> DefaultValue;
        Value -> Value
    end.

get_prefixed_env_var("RABBITMQ_" ++ Suffix = VarName) ->
    case get_env_var(VarName) of
        false -> get_env_var(Suffix);
        Value -> Value
    end.

get_prefixed_env_var(VarName, DefaultValue) ->
    case get_prefixed_env_var(VarName) of
        false -> DefaultValue;
        Value -> Value
    end.

normalize_path("" = Path) ->
    Path;
normalize_path(Path) ->
    filename:join(filename:split(Path)).

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

reason_to_sysexit(ex_usage)    -> 64;
reason_to_sysexit(ex_dataerr)  -> 65;
reason_to_sysexit(ex_software) -> 70;
reason_to_sysexit(ex_config)   -> 78.
