-module(rabbitmq_prelaunch_helpers).

-export([get_env_var/2,
         get_prefixed_env_var/2,
         get_sys_prefix/0,
         get_rabbitmq_base/0,
         get_node_name_type/0,
         get_node_name/1,
         exit/1]).

get_env_var(VarName, DefaultValue) ->
    case os:getenv(VarName) of
        false -> DefaultValue;
        ""    -> DefaultValue;
        Value -> Value
    end.

get_prefixed_env_var("RABBITMQ_" ++ Suffix = VarName, DefaultValue) ->
    case os:getenv(VarName) of
        false -> get_env_var(Suffix, DefaultValue);
        ""    -> get_env_var(Suffix, DefaultValue);
        Value -> Value
    end.

get_sys_prefix() ->
    get_env_var("SYS_PREFIX", "").

get_rabbitmq_base() ->
    case os:getenv("RABBITMQ_BASE") of
        false ->
            %% FIXME: Query !APPDATA!.
            AppData = "",
            filename:join(AppData, "RabbitMQ");
        Value ->
            Value
    end.

get_node_name_type() ->
    case os:getenv("RABBITMQ_NAME_TYPE") of
        "-sname" -> shortnames;
        "-name"  -> longnames;
        false    -> shortnames
    end.

get_node_name(NameType) ->
    LongHostname = net_adm:localhost(),
    ShortHostname = re:replace(LongHostname, "\\..*$", "", [{return, list}]),
    case os:getenv("RABBITMQ_NODENAME") of
        false when NameType =:= shortnames ->
            rabbit_nodes:make({"rabbit", ShortHostname});
        false when NameType =:= longnames ->
            rabbit_nodes:make({"rabbit", LongHostname});
        Value ->
            case string:find(Value, "@") of
                nomatch when NameType =:= shortnames ->
                    rabbit_nodes:make({Value, ShortHostname});
                nomatch when NameType =:= longnames ->
                    rabbit_nodes:make({Value, LongHostname});
                _ ->
                    rabbit_nodes:make(Value)
            end
    end.

exit(Reason) when is_atom(Reason) ->
    init:stop(reason_to_sysexit(Reason));
exit(Status) when is_integer(Status) ->
    init:stop(Status).

reason_to_sysexit(ex_usage)   -> 64;
reason_to_sysexit(ex_dataerr) -> 65;
reason_to_sysexit(ex_config)  -> 78.
