-module(rabbitmq_prelaunch_logging).

-export([setup/1]).

setup(Context) ->
    ok = set_ERL_CRASH_DUMP_envvar(Context),
    ok = configure_lager(Context).

set_ERL_CRASH_DUMP_envvar(#{log_base_dir := LogBaseDir}) ->
    case os:getenv("ERL_CRASH_DUMP") of
        false ->
            os:putenv("ERL_CRASH_DUMP",
                      filename:join(LogBaseDir, "erl_crash.dump")),
            ok;
        _ ->
            ok
    end.

configure_lager(#{log_base_dir := LogBaseDir,
                  main_log_file := MainLog,
                  upgrade_log_file := UpgradeLog}) ->
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
    ok = application:set_env(rabbit, lager_log_root, LogBaseDir),
    ok = application:set_env(rabbit, lager_default_file, MainLagerHandler),
    ok = application:set_env(rabbit, lager_upgrade_file, UpgradeLagerHandler),
    ok = application:set_env(lager, crash_log, "log/crash.log"),

    rabbit_lager:start_logger().
