-module(rabbitmq_prelaunch_dist).

-export([setup/1]).

setup(#{nodename := Node, nodename_type := NameType} = Context) ->
    rabbit_log_prelaunch:debug(""),
    rabbit_log_prelaunch:debug("== Erlang distribution =="),
    rabbit_log_prelaunch:debug("Node name: ~s (type: ~s)", [Node, NameType]),
    stop_mnesia(),
    ok = rabbit_nodes_common:ensure_epmd(),
    ok = duplicate_node_check(Context),
    ok = dist_port_range_check(Context),
    ok = dist_port_use_check(Context),

    ok = do_setup(Context),
    ok.

stop_mnesia() ->
    %% Stop Mnesia now. It is started because `rabbit` depends on it
    %% (and this `rabbitmq_prelaunch` too). But because distribution
    %% is not configured yet at the time it is started, it is
    %% non-functionnal. We can stop it now, setup distribution and
    %% `rabbit` will take care of starting it again.
    %%
    %% TODO: Move to distribution setup.
    rabbit_log_prelaunch:debug("Stopping Mnesia to setup distribution"),
    mnesia:stop().

do_setup(#{nodename := Node,
           nodename_type := NameType,
           erlang_dist_tcp_port := DistTcpPort}) ->
    ok = application:set_env(kernel, inet_dist_listen_min, DistTcpPort),
    ok = application:set_env(kernel, inet_dist_listen_max, DistTcpPort),

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

%% Check whether a node with the same name is already running
duplicate_node_check(#{split_nodename := {NodeName, NodeHost}}) ->
    PrelaunchName = rabbit_nodes:make(
                      {NodeName ++ "_prelaunch" ++ os:getpid(),
                       "localhost"}),
    {ok, _} = net_kernel:start([PrelaunchName, shortnames]),
    case rabbit_nodes:names(NodeHost) of
        {ok, NamePorts}  ->
            case proplists:is_defined(NodeName, NamePorts) of
                true ->
                    rabbit_log_prelaunch:error(
                      "Node with name ~p already running on ~p",
                      [NodeName, NodeHost]),
                    rabbitmq_prelaunch_helpers:exit(ex_config);
                false ->
                    net_kernel:stop(),
                    ok
            end;
        {error, EpmdReason} ->
            rabbit_log_prelaunch:error(
              "epmd error for host ~s: ~s",
              [NodeHost, rabbit_misc:format_inet_error(EpmdReason)]),
            rabbitmq_prelaunch_helpers:exit(ex_config)
    end.

dist_port_range_check(#{erlang_dist_tcp_port := DistTcpPort}) ->
    case DistTcpPort of
        _ when DistTcpPort < 1 orelse DistTcpPort > 65535 ->
            rabbit_log_prelaunch:error(
              "Invalid Erlang distribution TCP port: ~b", [DistTcpPort]),
            rabbitmq_prelaunch_helpers:exit(ex_config);
        _ ->
            ok
    end.

dist_port_use_check(#{split_nodename := {_, NodeHost},
                      erlang_dist_tcp_port := DistTcpPort}) ->
    dist_port_use_check_ipv4(NodeHost, DistTcpPort).

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
        [] ->
            rabbit_log_prelaunch:error(
              "Distribution port ~b in use on ~s "
              "(by non-Erlang process?)~n", [Port, Host]);
        [Name] ->
            rabbit_log_prelaunch:error(
              "Distribution port ~b in use by ~s@~s~n", [Port, Name, Host])
    end,
    rabbitmq_prelaunch_helpers:exit(ex_config).
