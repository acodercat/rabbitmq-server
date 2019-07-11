-module(rabbitmq_prelaunch).

-export([run/0]).

run() ->
    ok = run(node()),
    ignore.

run(nonode@nohost) ->
    %% Get informations to setup logging.
    Context0 = rabbitmq_prelaunch_env:get_context_before_logging_init(),

    %% Setup logging for the prelaunch phase.
    ok = rabbitmq_prelaunch_logging:enable_prelaunch_logging(Context0, true),

    %% Complete context now that we have logging enabled.
    Context = rabbitmq_prelaunch_env:get_context_after_logging_init(Context0),
    rabbitmq_prelaunch_env:log_context(Context),
    rabbitmq_prelaunch_env:context_to_app_env_vars(Context),

    %% 1. Write PID file
    write_pid_file(Context),

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
        _:{exit, Reason} ->
            remove_pid_file(Context),
            rabbitmq_prelaunch_helpers:exit(Reason);
        Class:Reason:Stacktrace ->
            rabbit_log_prelaunch:error(
              "Exception during prelaunch phase:"),
            [rabbit_log_prelaunch:error("~s", [Line])
             || Line <- string:split(
                          lager:pr_stacktrace(Stacktrace, {Class, Reason}),
                          [$\n],
                          all)],

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
                    rabbit_log_prelaunch:error(
                      "Failed to write PID file \"~s\": ~s",
                      [PidFile, file:format_error(Reason)]),
                    Error
            end;
        {error, Reason} = Error ->
            rabbit_log_prelaunch:error(
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
