-module(rabbitmq_prelaunch_logging).

-export([setup/1]).

setup(Context) ->
    %% Environment variables (IN):
    %%
    %%   RABBITMQ_LOG_BASE
    %%     Directory to write log files
    %%     Default: (Unix) ${SYS_PREFIX}/var/log/rabbitmq
    %%           (Windows) ${RABBITMQ_BASE}\log
    %%
    %%   RABBITMQ_LOGS
    %%     Main log file
    %%     Default: ${RABBITMQ_LOG_BASE}/${RABBITMQ_NODENAME}.log
    %%
    %%   RABBITMQ_UPDATE_LOG
    %%     Upgrade-procesure-specific log file
    %%     Default: ${RABBITMQ_LOG_BASE}/${RABBITMQ_NODENAME}_upgrade.log
    %%
    %% Environment variables (OUT):
    %%
    %%   ERL_CRASH_DUMP
    %%     Erlang VM crash dump file
    %%     Default: ${RABBITMQ_LOG_BASE}/erl_crash.dump
    %%
    %% Application environment (OUT):
    %%   sasl   sasl_error_logger
    %%   sasl   errlog_type
    %%   rabbit lager_log_root
    %%   rabbit lager_default_file
    %%   rabbit lager_upgrade_file

    LogBase = get_log_base_path(Context),

    case os:getenv("ERL_CRASH_DUMP") of
        false ->
            os:putenv("ERL_CRASH_DUMP",
                      filename:join(LogBase, "erl_crash.dump"));
        _ ->
            ok
    end,

    MainLog = get_main_log_path(Context, LogBase),
    UpgradeLog = get_upgrade_log_path(Context, LogBase),

    {SaslErrorLogger,
     MainLagerHandler,
     UpgradeLagerHandler} = case MainLog of
                                "-" ->
                                    %% Log to STDOUT.
                                    {tty,
                                     tty,
                                     tty};
                                _ ->
                                    %% Log to file.
                                    {false,
                                     MainLog,
                                     UpgradeLog}
                            end,

    ok = application:set_env(sasl, errlog_type, error),
    ok = application:set_env(sasl, sasl_error_logger, SaslErrorLogger),
    ok = application:set_env(rabbit, lager_log_root, LogBase),
    ok = application:set_env(rabbit, lager_default_file, MainLagerHandler),
    ok = application:set_env(rabbit, lager_upgrade_file, UpgradeLagerHandler),

    rabbit_lager:start_logger().

get_log_base_path(#{os_type := {unix, _}}) ->
    SysPrefix = rabbitmq_prelaunch_helpers:get_sys_prefix(),
    rabbitmq_prelaunch_helpers:get_prefixed_env_var(
      "RABBITMQ_LOG_BASE", SysPrefix ++ "/var/log/rabbitmq");
get_log_base_path(#{os_type := {win32, _}}) ->
    RabbitmqBase = rabbitmq_prelaunch_helpers:get_rabbitmq_base(),
    rabbitmq_prelaunch_helpers:get_prefixed_env_var(
      "RABBITMQ_LOG_BASE", filename:join(RabbitmqBase, "log")).

get_main_log_path(#{nodename := Nodename}, LogBase) ->
    Default = filename:join(LogBase, atom_to_list(Nodename) ++ ".log"),
    rabbitmq_prelaunch_helpers:get_prefixed_env_var("RABBITMQ_LOGS", Default).

get_upgrade_log_path(#{nodename := Nodename}, LogBase) ->
    Default = filename:join(LogBase, atom_to_list(Nodename) ++ "_upgrade.log"),
    rabbitmq_prelaunch_helpers:get_env_var("RABBITMQ_UPGRADE_LOG", Default).
