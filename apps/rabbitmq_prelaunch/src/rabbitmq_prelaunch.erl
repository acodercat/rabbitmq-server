-module(rabbitmq_prelaunch).

-export([run/0]).

run() ->
    ok = run(node()),
    ignore.

run(nonode@nohost) ->
    Context = try
                  %% Get informations to setup logging.
                  Context0 = rabbit_env:get_context_before_logging_init(false),

                  %% Set code path.
                  rabbit_env:context_to_code_path(Context0),

                  %% Setup logging for the prelaunch phase.
                  ok = rabbitmq_prelaunch_logging:enable_prelaunch_logging(
                         Context0, true),

                  %% Complete context now that we have logging enabled.
                  rabbit_env:get_context_after_logging_init(Context0)
              catch
                  _:{exit, Reason1} ->
                      rabbitmq_prelaunch_helpers:exit(Reason1);
                  Class1:Reason1:Stacktrace1 ->
                      log_exception(Class1, Reason1, Stacktrace1, false),
                      rabbitmq_prelaunch_helpers:exit(ex_software)
              end,

    rabbit_env:log_context(Context),
    rabbit_env:context_to_app_env_vars(Context),

    %% 1. Write PID file
    _ = write_pid_file(Context),

    %% If one step fails, we remove the PID file and exit with the
    %% provided status code.
    try
        %% 2. Feature flags registry
        ok = rabbitmq_prelaunch_feature_flags:setup(Context),

        %% 3. Configuration check + loading
        ok = rabbitmq_prelaunch_conf:setup(Context),

        %% 4. Logging
        ok = rabbitmq_prelaunch_logging:setup(Context),

        %% 5. HiPE compilation
        ok = rabbitmq_prelaunch_hipe:setup(Context),

        %% 6. Erlang distribution check + start
        ok = rabbitmq_prelaunch_dist:setup(Context),

        %% 7. Clustering
        ok = rabbitmq_prelaunch_cluster:setup(Context)
    catch
        _:{exit, Reason2} ->
            remove_pid_file(Context),
            rabbitmq_prelaunch_helpers:exit(Reason2);
        Class2:Reason2:Stacktrace2 ->
            log_exception(Class2, Reason2, Stacktrace2, true),
            remove_pid_file(Context),
            rabbitmq_prelaunch_helpers:exit(ex_software)
    end;
run(_) ->
    ok.

write_pid_file(#{pid_file := PidFile}) ->
    rabbit_log_prelaunch:debug("Writing PID file: ~s", [PidFile]),
    Parent = filename:dirname(PidFile),
    case rabbitmq_prelaunch_helpers:mkdir_p(Parent) of
        ok ->
            OSPid = os:getpid(),
            case file:write_file(PidFile, OSPid) of
                ok ->
                    ok;
                {error, Reason} = Error ->
                    rabbit_log_prelaunch:warning(
                      "Failed to write PID file \"~s\": ~s",
                      [PidFile, file:format_error(Reason)]),
                    Error
            end;
        {error, Reason} = Error ->
            rabbit_log_prelaunch:warning(
              "Failed to create PID file \"~s\" directory: ~s",
              [PidFile, file:format_error(Reason)]),
            Error
    end;
write_pid_file(_) ->
    ok.

remove_pid_file(#{pid_file := PidFile}) ->
    file:delete(PidFile);
remove_pid_file(_) ->
    ok.

log_exception(Class, Reason, Stacktrace, true) ->
    rabbit_log_prelaunch:error("Exception during prelaunch phase:"),
    [rabbit_log_prelaunch:error("~s", [Line])
     || Line <- string:split(
                  lager:pr_stacktrace(Stacktrace, {Class, Reason}),
                  [$\n],
                  all)];
log_exception(Class, Reason, Stacktrace, false) ->
    io:format(standard_error, "Exception during prelaunch phase:~n", []),
    [io:format(standard_error, "~s~n", [Line])
     || Line <- string:split(
                  lager:pr_stacktrace(Stacktrace, {Class, Reason}),
                  [$\n],
                  all)].
