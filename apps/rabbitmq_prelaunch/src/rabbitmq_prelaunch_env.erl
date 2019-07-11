-module(rabbitmq_prelaunch_env).

-export([get_context_before_logging_init/0,
         get_context_after_logging_init/1,
         log_context/1,
         context_to_app_env_vars/1,
         context_to_app_env_vars_no_logging/1]).

get_context_before_logging_init() ->
    %% The order of steps below is important because some of them
    %% depends on previous steps.
    Steps = [
             fun node_name_and_type/1,
             fun log_levels/1,
             fun config_files/1,
             fun log_files/1,
             fun mnesia_dir/1,
             fun quorum_dir/1,
             fun pid_file/1,
             fun feature_flags_file/1,
             fun plugins_dirs/1
            ],

    run_context_steps(context_base(), Steps).

get_context_after_logging_init(EarlyContext) ->
    %% The order of steps below is important because some of them
    %% depends on previous steps.
    Steps = [
             fun tcp_configuration/1
            ],

    run_context_steps(EarlyContext, Steps).

context_base() ->
    OSType = os:type(),
    #{os_type => OSType}.

run_context_steps(Context, Steps) ->
    lists:foldl(
      fun(Step, Context1) -> Step(Context1) end,
      Context,
      Steps).

log_context(Context) ->
    rabbit_log_prelaunch:debug("Context (based on environment variables):"),
    lists:foreach(
      fun(Key) ->
              Value = maps:get(Key, Context),
              rabbit_log_prelaunch:debug("  - ~s: ~p", [Key, Value])
      end,
      lists:sort(maps:keys(Context))).

context_to_app_env_vars(Context) ->
    rabbit_log_prelaunch:debug(
      "Setting default application environment variables:"),
    Fun = fun({App, Param, Value}) ->
                  rabbit_log_prelaunch:debug(
                    "  - ~s:~s = ~p", [App, Param, Value]),
                  ok = application:set_env(
                         App, Param, Value, [{persistent, true}])
          end,
    context_to_app_env_vars1(Context, Fun).

context_to_app_env_vars_no_logging(Context) ->
    Fun = fun({App, Param, Value}) ->
                  ok = application:set_env(
                         App, Param, Value, [{persistent, true}])
          end,
    context_to_app_env_vars1(Context, Fun).

context_to_app_env_vars1(
  #{erlang_dist_tcp_port := DistTcpPort,
    mnesia_dir := MnesiaDir,
    feature_flags_file := FFFile,
    quorum_queue_dir := QuorumQueueDir,
    plugins_path := PluginsPath,
    plugins_expand_dir := PluginsExpandDir,
    enabled_plugins_file := EnabledPluginsFile} = Context,
  Fun) ->
    lists:foreach(
      Fun,
      %% Those are all the application environment variables which
      %% were historically set on the erl(1) command line in
      %% rabbitmq-server(8).
      [{kernel, inet_dist_listen_min, DistTcpPort},
       {kernel, inet_dist_listen_max, DistTcpPort},
       {kernel, inet_default_connect_options, [{nodelay, true}]},
       {sasl, errlog_type, error},
       {os_mon, start_cpu_sup, false},
       {os_mon, start_disksup, false},
       {os_mon, start_memsup, false},
       {mnesia, dir, MnesiaDir},
       {ra, data_dir, QuorumQueueDir},
       {rabbit, feature_flags_file, FFFile},
       {rabbit, plugins_dir, PluginsPath},
       {rabbit, plugins_expand_dir, PluginsExpandDir},
       {rabbit, enabled_plugins_file, EnabledPluginsFile}]),

    case Context of
        #{amqp_ipaddr_and_tcp_port := {IpAddr, TcpPort}}
          when IpAddr /= undefined andalso TcpPort /= undefined ->
            Fun({rabbit, tcp_listeners, [{IpAddr, TcpPort}]});
        _ ->
            ok
    end,
    ok.

%% -------------------------------------------------------------------
%%
%% RABBITMQ_NODENAME
%%   Erlang node name.
%%   Default: rabbit@<hostname>
%%
%% RABBITMQ_USE_LONGNAME
%%   Main configuration file.
%%   Extension is optional. `.config` for the old rlang-term-based
%%   format, `.conf` for the new Cuttlefish-based format.
%%   Default: (Unix) ${SYS_PREFIX}/etc/rabbitmq/rabbitmq
%%         (Windows) ${RABBITMQ_BASE}\rabbitmq

node_name_and_type(Context) ->
    NameType = get_node_name_type(),
    Nodename = get_node_name(NameType),
    Context#{nodename => Nodename,
             split_nodename => rabbit_nodes:parts(Nodename),
             nodename_type => NameType}.

get_node_name_type() ->
    UseLongname = get_prefixed_env_var("RABBITMQ_USE_LONGNAME"),
    case UseLongname of
        "true" -> longnames;
        _      -> shortnames
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

%% -------------------------------------------------------------------
%%
%% RABBITMQ_CONFIG_FILE
%%   Main configuration file
%%   Extension is optional. `.config` for the old rlang-term-based
%%   format, `.conf` for the new Cuttlefish-based format.
%%   Default: (Unix) ${SYS_PREFIX}/etc/rabbitmq/rabbitmq
%%         (Windows) ${RABBITMQ_BASE}\rabbitmq
%%
%% RABBITMQ_ADVANCED_CONFIG_FILE
%%   Advanced configuration file
%%   Erlang-term-based format with a `.config` extension.
%%   Default: (Unix) ${SYS_PREFIX}/etc/rabbitmq/advanced.config
%%         (Windows) ${RABBITMQ_BASE}\advanced.config
%%
%% TODO:
%%
%% RABBITMQ_SCHEMA_DIR
%%   Directory where all detected Cuttlefish schemas are written
%%   Default: (Unix) ${SYS_PREFIX}/var/lib/rabbitmq/schema
%%         (Windows) ${RABBITMQ_BASE}\schema
%%
%% RABBITMQ_GENERATED_CONFIG_DIR
%%   Directory where final configuration (generated from
%%   Cuttlefish-based configuration) is written
%%   Default: (Unix) ${SYS_PREFIX}/var/lib/rabbitmq/config
%%         (Windows) ${RABBITMQ_BASE}\config

config_files(Context) ->
    ConfigBaseDir = get_config_base_dir(Context),
    MainConfigFileNoEx = get_main_config_file_noex(ConfigBaseDir),
    AdvancedConfigFileNoEx = get_advanced_config_file_noex(ConfigBaseDir),
    Context#{config_base_dir => ConfigBaseDir,
             main_config_file_noex => MainConfigFileNoEx,
             advanced_config_file_noex => AdvancedConfigFileNoEx}.

get_config_base_dir(#{os_type := {unix, _}}) ->
    SysPrefix = get_sys_prefix(),
    Dir = filename:join([SysPrefix, "etc", "rabbitmq"]),
    normalize_path(Dir);
get_config_base_dir(#{os_type := {win32, _}}) ->
    Dir = get_rabbitmq_base(),
    normalize_path(Dir).

get_main_config_file_noex(ConfigBaseDir) ->
    File = get_prefixed_env_var(
             "RABBITMQ_CONFIG_FILE",
             filename:join(ConfigBaseDir, "rabbitmq")),
    File1 = re:replace(File, "\\.(conf|config)$", "", [{return, list}]),
    normalize_path(File1).

get_advanced_config_file_noex(ConfigBaseDir) ->
    File = get_prefixed_env_var(
             "RABBITMQ_ADVANCED_CONFIG_FILE",
             filename:join(ConfigBaseDir, "advanced")),
    File1 = re:replace(File, "\\.config$", "", [{return, list}]),
    normalize_path(File1).

%% -------------------------------------------------------------------
%%
%% RABBITMQ_LOG_BASE
%%   Directory to write log files
%%   Default: (Unix) ${SYS_PREFIX}/var/log/rabbitmq
%%         (Windows) ${RABBITMQ_BASE}\log
%%
%% RABBITMQ_LOGS
%%   Main log file
%%   Default: ${RABBITMQ_LOG_BASE}/${RABBITMQ_NODENAME}.log
%%
%% RABBITMQ_UPDATE_LOG
%%   Upgrade-procesure-specific log file
%%   Default: ${RABBITMQ_LOG_BASE}/${RABBITMQ_NODENAME}_upgrade.log
%%
%% RABBITMQ_LOG
%%   Log level; overrides the configuration file value
%%   Default: (undefined)

log_levels(Context) ->
    LogLevels = get_log_levels(),
    Context#{log_levels => LogLevels}.

log_files(Context) ->
    LogBaseDir = get_log_base_dir(Context),
    MainLogFile = get_main_log_file(Context, LogBaseDir),
    UpgradeLogFile = get_upgrade_log_file(Context, LogBaseDir),
    Context#{log_base_dir => LogBaseDir,
             main_log_file => MainLogFile,
             upgrade_log_file => UpgradeLogFile}.

get_log_levels() ->
    LogValue = get_prefixed_env_var("RABBITMQ_LOG"),
    case LogValue of
        false -> undefined;
        _     -> get_log_levels1(string:lexemes(LogValue, ","), #{})
    end.

get_log_levels1([CategoryValue | Rest], Result) ->
    case string:lexemes(CategoryValue, "=") of
        ["+color"] ->
            Result1 = Result#{color => true},
            get_log_levels1(Rest, Result1);
        ["-color"] ->
            Result1 = Result#{color => false},
            get_log_levels1(Rest, Result1);
        [CategoryOrLevel] ->
            case parse_level(CategoryOrLevel) of
                undefined ->
                    Result1 = Result#{CategoryOrLevel => debug},
                    get_log_levels1(Rest, Result1);
                Level ->
                    Result1 = Result#{global => Level},
                    get_log_levels1(Rest, Result1)
            end;
        [Category, Level0] ->
            case parse_level(Level0) of
                undefined ->
                    get_log_levels1(Rest, Result);
                Level ->
                    Result1 = Result#{Category => Level},
                    get_log_levels1(Rest, Result1)
            end
    end;
get_log_levels1([], Result) ->
    Result.

parse_level("debug")     -> debug;
parse_level("info")      -> info;
parse_level("notice")    -> notice;
parse_level("warning")   -> warning;
parse_level("error")     -> error;
parse_level("critical")  -> critical;
parse_level("alert")     -> alert;
parse_level("emergency") -> emergency;
parse_level("none")      -> none;
parse_level(_)           -> undefined.

get_log_base_dir(#{os_type := {unix, _}}) ->
    SysPrefix = get_sys_prefix(),
    Default = filename:join([SysPrefix, "etc", "rabbitmq"]),
    normalize_path(get_prefixed_env_var("RABBITMQ_LOG_BASE", Default));
get_log_base_dir(#{os_type := {win32, _}}) ->
    RabbitmqBase = get_rabbitmq_base(),
    Default = filename:join([RabbitmqBase, "log"]),
    normalize_path(get_prefixed_env_var("RABBITMQ_LOG_BASE", Default)).

get_main_log_file(#{nodename := Nodename}, LogBaseDir) ->
    Default = filename:join(LogBaseDir, atom_to_list(Nodename) ++ ".log"),
    Value = get_prefixed_env_var("RABBITMQ_LOGS", Default),
    case Value of
        "-" -> Value;
        _   -> normalize_path(Value)
    end.

get_upgrade_log_file(#{nodename := Nodename}, LogBaseDir) ->
    Default = filename:join(LogBaseDir,
                            atom_to_list(Nodename) ++ "_upgrade.log"),
    normalize_path(get_prefixed_env_var("RABBITMQ_UPGRADE_LOG", Default)).

%% -------------------------------------------------------------------
%%
%% RABBITMQ_MNESIA_BASE
%%   Directory where to create Mnesia directory.
%%   Default: (Unix) ${SYS_PREFIX}/var/lib/rabbitmq/mnesia
%%         (Windows) ${RABBITMQ_BASE}/db
%%
%% RABBITMQ_MNESIA_DIR
%%   Directory where to put Mnesia data.
%%   Default: ${RABBITMQ_MNESIA_BASE}/${RABBITMQ_NODENAME}

mnesia_dir(Context) ->
    MnesiaBaseDir = get_mnesia_base_dir(Context),
    MnesiaDir = get_mnesia_dir(Context, MnesiaBaseDir),
    Context#{mnesia_base_dir => MnesiaBaseDir,
             mnesia_dir => MnesiaDir}.

get_mnesia_base_dir(Context) ->
    Default = get_default_mnesia_base_dir(Context),
    Dir = get_prefixed_env_var("RABBITMQ_MNESIA_BASE", Default),
    normalize_path(Dir).

get_default_mnesia_base_dir(Context) ->
    DataDir = get_rabbitmq_data_dir(Context),
    Basename = case Context of
                   #{os_type := {unix, _}}  -> "mnesia";
                   #{os_type := {win32, _}} -> "db"
               end,
    filename:join(DataDir, Basename).

get_mnesia_dir(#{nodename := Nodename}, MnesiaBaseDir) ->
    Dir = get_prefixed_env_var(
            "RABBITMQ_MNESA_DIR",
            filename:join(MnesiaBaseDir, Nodename)),
    normalize_path(Dir).

%% -------------------------------------------------------------------
%%
%% RABBITMQ_QUORUM_DIR
%%   Directory where to store Ra state for quorum queues.
%%   Default: ${RABBITMQ_MNESIA_DIR}/quorum

quorum_dir(Context) ->
    QuorumQueueDir = get_quorum_queue_dir(Context),
    Context#{quorum_queue_dir => QuorumQueueDir}.

get_quorum_queue_dir(#{mnesia_dir := MnesiaDir}) ->
    Default = filename:join(MnesiaDir, "quorum"),
    Dir = get_prefixed_env_var("RABBITMQ_QUORUM_DIR", Default),
    normalize_path(Dir).

%% -------------------------------------------------------------------
%%
%% RABBITMQ_PID_FILE [Unix only]
%%   File used to write the Erlang VM OS PID.
%%   Default: ${RABBITMQ_MNESIA_DIR}.pid

pid_file(#{os_type := {unix, _}} = Context) ->
    PidFile = get_pid_file_path(Context),
    Context#{pid_file => PidFile};
pid_file(#{os_type := {win32, _}} = Context) ->
    Context.

get_pid_file_path(#{mnesia_base_dir := MnesiaBaseDir,
                    nodename := Nodename}) ->
    File = get_prefixed_env_var(
             "RABBITMQ_PID_FILE",
             filename:join(MnesiaBaseDir, atom_to_list(Nodename) ++ ".pid")),
    normalize_path(File).

%% -------------------------------------------------------------------
%%
%% RABBITMQ_FEATURE_FLAGS_FILE
%%   File used to store enabled feature flags.
%%   Default: ${RABBITMQ_MNESIA_BASE}/${RABBITMQ_NODENAME}-feature_flags

feature_flags_file(Context) ->
    FFFile = get_feature_flags_file(Context),
    Context#{feature_flags_file => FFFile}.

get_feature_flags_file(#{mnesia_base_dir := MnesiaBaseDir,
                         nodename := Nodename}) ->
    Default = filename:join(MnesiaBaseDir,
                            atom_to_list(Nodename) ++ "-feature_flags"),
    File = get_env_var("RABBITMQ_FEATURE_FLAGS_FILE", Default),
    normalize_path(File).

%% -------------------------------------------------------------------
%%
%% RABBITMQ_PLUGINS_DIR
%%   List of directories where to look for plugins.
%%   Directories are separated by:
%%     ':' on Unix
%%     ';' on Windows
%%   Default: ${RABBITMQ_HOME}/plugins
%%
%% RABBITMQ_ENABLED_PLUGINs_FILE
%%   File where the list of enabled plugins is stored.
%%   Default: (Unix) ${SYS_PREFIX}/etc/rabbitmq/enabled_plugins
%%         (Windows) ${RABBITMQ_BASE}\enabled_plugins

plugins_dirs(Context) ->
    PluginsPath = get_plugins_path(),
    PluginsExpandDir = get_plugins_expand_dir(Context),
    EnabledPluginsFile = get_enabled_plugins_file(Context),
    Context#{plugins_path => PluginsPath,
             plugins_expand_dir => PluginsExpandDir,
             enabled_plugins_file => EnabledPluginsFile}.

get_plugins_path() ->
    get_prefixed_env_var("RABBITMQ_PLUGINS_DIR", get_default_plugins_path()).

get_default_plugins_path() ->
    case rabbitmq_prelaunch_helpers:is_dev_environment() of
        false ->
            CommonPlugin = code:lib_dir(rabbit_common),
            filename:dirname(CommonPlugin);
        true ->
            {ok, Cwd} = file:get_cwd(),
            filename:join(Cwd, "plugins")
    end.

get_plugins_expand_dir(#{mnesia_base_dir := MnesiaBaseDir,
                         nodename := Nodename}) ->
    get_prefixed_env_var(
      "RABBITMQ_PLUGINS_EXPAND_DIR",
      filename:join(MnesiaBaseDir,
                    atom_to_list(Nodename) ++ "-plugins-expand")).

get_enabled_plugins_file(Context) ->
    ConfigBaseDir = get_config_base_dir(Context),
    Default = filename:join(ConfigBaseDir, "enabled_plugins"),
    get_prefixed_env_var("RABBITMQ_ENABLED_PLUGINS_FILE", Default).

%% -------------------------------------------------------------------
%%
%% RABBITMQ_NODE_IP_ADDRESS
%%   AMQP TCP IP address to listen on
%%   Default: unset (i.e. listen on all interfaces)
%%
%% RABBITMQ_NODE_PORT
%%   AMQP TCP port.
%%   Default: 5672
%%
%% RABBITMQ_DIST_PORT
%%   Erlang distribution TCP port.
%%   Default: ${RABBITMQ_NODE_PORT} + 20000

tcp_configuration(Context) ->
    AmqpIpAddress = get_amqp_ipaddr(),
    AmqpTcpPort = get_amqp_tcp_port(),
    DistTcpPort = get_erlang_dist_tcp_port(AmqpTcpPort),
    Context#{amqp_ipaddr_and_tcp_port => {AmqpIpAddress, AmqpTcpPort},
             erlang_dist_tcp_port => DistTcpPort}.

get_amqp_ipaddr() ->
    get_prefixed_env_var("RABBITMQ_NODE_IP_ADDRESS", "auto").

get_amqp_tcp_port() ->
    Default = 5672,
    case get_prefixed_env_var("RABBITMQ_NODE_PORT") of
        false ->
            Default;
        TcpPortStr ->
            try
                erlang:list_to_integer(TcpPortStr)
            catch
                _:badarg ->
                    rabbit_log_prelaunch:error(
                      "Invalid value for $RABBITMQ_NODE_PORT: ~p",
                      [TcpPortStr]),
                    rabbitmq_prelaunch_helpers:exit(ex_config)
            end
    end.

get_erlang_dist_tcp_port(AmqpTcpPort) ->
    Default = AmqpTcpPort + 20000,
    case get_prefixed_env_var("RABBITMQ_DIST_PORT") of
        false ->
            Default;
        TcpPortStr ->
            try
                erlang:list_to_integer(TcpPortStr)
            catch
                _:badarg ->
                    rabbit_log_prelaunch:error(
                      "Invalid value for $RABBITMQ_DIST_PORT: ~p",
                      [TcpPortStr]),
                    rabbitmq_prelaunch_helpers:exit(ex_config)
            end
    end.

%% -------------------------------------------------------------------
%%
%%  SYS_PREFIX [Unix only]
%%    Default: ""
%%
%%  RABBITMQ_BASE [Windows only]
%%    Directory where to put RabbitMQ data.
%%    Default: !APPDATA!\RabbitMQ

get_rabbitmq_data_dir(#{os_type := {unix, _}}) ->
    SysPrefix = get_sys_prefix(),
    filename:join([SysPrefix, "var", "lib", "rabbitmq"]);
get_rabbitmq_data_dir(#{os_type := {win32, _}}) ->
    get_rabbitmq_base().

get_sys_prefix() ->
    normalize_path(get_env_var("SYS_PREFIX", "")).

get_rabbitmq_base() ->
    case get_env_var("RABBITMQ_BASE") of
        false ->
            AppData = get_env_var("APPDATA"),
            filename:join(AppData, "RabbitMQ");
        Value ->
            normalize_path(Value)
    end.

%% -------------------------------------------------------------------
%% Helpers.
%% -------------------------------------------------------------------

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
