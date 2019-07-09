-module(rabbitmq_prelaunch).

-export([run/0]).

run() ->
    ok = run(node()),
    ignore.

run(nonode@nohost) ->
    %% Prepare minimal informations to setup logging.
    EarlyContext = rabbitmq_prelaunch_env:get_early_context(),

    %% Setup minimum logging for the prelaunch phase.
    ok = rabbitmq_prelaunch_logging:enable_prelaunch_logging(
           EarlyContext, true),

    %% Prepare more informations required during setup.
    Context = rabbitmq_prelaunch_env:get_context(EarlyContext),
    rabbitmq_prelaunch_env:log_context(Context),

    %% 1. Write PID file
    write_pid_file(Context),

    %% If one step fails, we remove the PID file and exit with the
    %% provided status code.
    try
        %% 2. Verify valid config file naming
        %% 3. Cuttlefish (pass #1)
        ok = rabbitmq_prelaunch_conf:setup(Context),

        %% 4. Logging
        ok = rabbitmq_prelaunch_logging:setup(Context),

        %% 5. Feature flags registry (including plugins)

        %% 6. Remaining environment variables -> configuration
        %% 7. Checking configuration
        %% 8. Checking+setting up distribution
        ok = rabbitmq_prelaunch_dist:setup(Context)
    catch
        _:{exit, Reason} ->
            remove_pid_file(Context),
            rabbitmq_prelaunch_helpers:exit(Reason)
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
