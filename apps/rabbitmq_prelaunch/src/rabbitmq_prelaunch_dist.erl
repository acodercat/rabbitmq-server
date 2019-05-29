-module(rabbitmq_prelaunch_dist).

-export([setup/1]).

setup(#{nodename := Node, nodename_type := NameType}) ->
    {NodeName, NodeHost} = rabbit_nodes:parts(Node),
    ok = rabbit_nodes_common:ensure_epmd(),
    ok = duplicate_node_check(NodeName, NodeHost),
    ok = dist_port_set_check(),
    ok = dist_port_range_check(),
    ok = dist_port_use_check(NodeHost),
    ok = config_file_check(),

    ok = do_setup(Node, NameType),
    ok.

get_dist_port() ->
    NodePort = case os:getenv("RABBITMQ_NODE_PORT") of
                   false  -> 5672;
                   ""     -> 5672;
                   Value1 -> erlang:list_to_integer(Value1)
               end,
    case os:getenv("RABBITMQ_DIST_PORT") of
        false -> NodePort + 20000;
        ""    -> NodePort + 20000;
        Value2 -> erlang:list_to_integer(Value2)
    end.

do_setup(Node, NameType) ->
    DistPort = get_dist_port(),
    ok = application:set_env(kernel, inet_dist_listen_min, DistPort),
    ok = application:set_env(kernel, inet_dist_listen_max, DistPort),

    case application:get_env(kernel, net_ticktime) of
        {ok, Ticktime} when is_integer(Ticktime) andalso Ticktime >= 1 ->
            %% The value passed to net_kernel:start/1 is the
            %% "minimum transition traffic interval" as defined in
            %% net_kernel:set_net_ticktime/1.
            MTTI = Ticktime * 1000 div 4,
            {ok, _} = net_kernel:start([Node, NameType, MTTI]);
        _ ->
            {ok, _} = net_kernel:start([Node, NameType])
    end,
    ok.

config_file_check() ->
    case rabbit_config:validate_config_files() of
        ok -> ok;
        {error, {ErrFmt, ErrArgs}} ->
            ErrMsg = io_lib:format(ErrFmt, ErrArgs),
            {{Year, Month, Day}, {Hour, Minute, Second, Milli}} = lager_util:localtime_ms(),
            io:format(standard_error, "~b-~2..0b-~2..0b ~2..0b:~2..0b:~2..0b.~b [error] ~s",
                      [Year, Month, Day, Hour, Minute, Second, Milli, ErrMsg]),
            throw(invalid_config_files)
    end.

%% Check whether a node with the same name is already running
duplicate_node_check(NodeName, NodeHost) ->
    PrelaunchName = rabbit_nodes:make({NodeName ++ "_prelaunch", "localhost"}),
    {ok, _} = net_kernel:start([PrelaunchName, shortnames]),
    case rabbit_nodes:names(NodeHost) of
        {ok, NamePorts}  ->
            case proplists:is_defined(NodeName, NamePorts) of
                true -> io:format(
                          "ERROR: node with name ~p already running on ~p~n",
                          [NodeName, NodeHost]),
                        throw(node_name_already_in_use);
                false ->
                    net_kernel:stop(),
                    ok
            end;
        {error, EpmdReason} ->
            io:format("ERROR: epmd error for host ~s: ~s~n",
                      [NodeHost, rabbit_misc:format_inet_error(EpmdReason)]),
            throw(failed_to_communicate_with_epmd)
    end.

dist_port_set_check() ->
    case get_config(os:getenv("RABBITMQ_CONFIG_ARG_FILE")) of
        {ok, [Config]} ->
            Kernel = rabbit_misc:pget(kernel, Config, []),
            case {rabbit_misc:pget(inet_dist_listen_min, Kernel, none),
                  rabbit_misc:pget(inet_dist_listen_max, Kernel, none)} of
                {none, none} -> ok;
                _            -> ok %rabbit_misc:quit(?DO_NOT_SET_DIST_PORT)
            end;
        {ok, _} ->
            ok;
        {error, _} ->
            ok
    end.

get_config("") -> {error, nofile};
get_config(File)  ->
    case consult_file(File) of
        {ok, Contents} -> {ok, Contents};
        {error, _} = E -> E
    end.

consult_file(false) -> {error, nofile};
consult_file(File)  ->
    FileName = case filename:extension(File) of
        ""        -> File ++ ".config";
        ".config" -> File;
        _         -> ""
    end,
    file:consult(FileName).

dist_port_range_check() ->
    case os:getenv("RABBITMQ_DIST_PORT") of
        false   -> ok;
        PortStr -> case catch list_to_integer(PortStr) of
                       Port when is_integer(Port) andalso Port > 65535 ->
                           ok; %rabbit_misc:quit(?DO_NOT_SET_DIST_PORT);
                       _ ->
                           ok
                   end
    end.

dist_port_use_check(NodeHost) ->
    case os:getenv("RABBITMQ_DIST_PORT") of
        false   -> ok;
        PortStr -> Port = list_to_integer(PortStr),
                   dist_port_use_check_ipv4(NodeHost, Port)
    end.

dist_port_use_check_ipv4(NodeHost, Port) ->
    case gen_tcp:listen(Port, [inet, {reuseaddr, true}]) of
        {ok, Sock} -> gen_tcp:close(Sock);
        {error, einval} -> dist_port_use_check_ipv6(NodeHost, Port);
        {error, _} -> dist_port_use_check_fail(Port, NodeHost)
    end.

dist_port_use_check_ipv6(NodeHost, Port) ->
    case gen_tcp:listen(Port, [inet6, {reuseaddr, true}]) of
        {ok, Sock} -> gen_tcp:close(Sock);
        {error, _} -> dist_port_use_check_fail(Port, NodeHost)
    end.

-spec dist_port_use_check_fail(non_neg_integer(), string()) ->
                                         no_return().

dist_port_use_check_fail(Port, Host) ->
    {ok, Names} = rabbit_nodes:names(Host),
    case [N || {N, P} <- Names, P =:= Port] of
        []     -> io:format("ERROR: distribution port ~b in use on ~s "
                            "(by non-Erlang process?)~n", [Port, Host]);
        [Name] -> io:format("ERROR: distribution port ~b in use by ~s@~s~n",
                            [Port, Name, Host])
    end,
    throw(dist_port_already_in_use).
