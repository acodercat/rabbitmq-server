-module(rabbitmq_prelaunch_logging).

-export([enable_prelaunch_logging/1,
         setup/1]).

enable_prelaunch_logging(#{log_levels := LogLevels}) ->
    LogLevel = case LogLevels of
                   #{"prelaunch" := Level} -> Level;
                   #{global := Level}      -> Level;
                   _                       -> warning
               end,
    Colored = case LogLevels of
                  #{color := true} -> true;
                  _                -> false
              end,
    ConsoleBackend = lager_console_backend,
    ConsoleOptions = [{level, LogLevel}],
    application:set_env(lager, colored, Colored),
    lager_app:start_handler(lager_event, ConsoleBackend, ConsoleOptions),
    lager_app:configure_sink(
      rabbit_log_prelaunch_lager_event,
      [{handlers, [{ConsoleBackend, ConsoleOptions}]}]),
    ok.

setup(Context) ->
    rabbit_log_prelaunch:debug("== Logging =="),
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
