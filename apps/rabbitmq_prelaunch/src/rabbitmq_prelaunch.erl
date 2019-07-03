-module(rabbitmq_prelaunch).

-export([run/0]).

run() ->
    ok = run(node()),
    ignore.

run(nonode@nohost) ->
    %% Prepare some informations required during setup.
    Context = rabbitmq_prelaunch_env:get_context(),

    %% Setup minimum logging for the prelaunch phase.
    ok = rabbitmq_prelaunch_logging:enable_prelaunch_logging(Context),
    rabbitmq_prelaunch_env:log_context(Context),

    %% Stop Mnesia now. It is started because `rabbit` depends on it
    %% (and this `rabbitmq_prelaunch` too). But because distribution
    %% is not configured yet at the time it is started, it is
    %% non-functionnal. We can stop it now, setup distribution and
    %% `rabbit` will take care of starting it again.
    io:format(standard_error, "Lager: ~p~n~p~n", [lager:status(), application:get_all_env(lager)]),
    rabbit_log_prelaunch:error("Stopping Mnesia to setup distribution"),
    mnesia:stop(),

    %% TODO: Add a small logging facility to log warnings and errors,
    %% and help debug this application before the actual logger is
    %% ready.
    %%
    %% It could be something which wraps the final logger and writes to
    %% stderr before it is ready.

    %% 1. Write PID file
    ok = write_pid_file(Context),

    %% If one step fails, we remove the PID file and exit with the
    %% provided status code.
    try
        %% ---------------------- Phase 1 ----------------------
        %% Here, we do the minimum to be ready for the next phase.
        %% Basically we need the main configuration to know:
        %%     - paths to log files
        %%     - where to extract plugins

        %% 2. Verify valid config file naming
        %% 3. Cuttlefish (pass #1)
        ok = rabbitmq_prelaunch_conf:setup(Context),

        %% 4. Logging
        ok = rabbitmq_prelaunch_logging:setup(Context),

        %% 5. Plugins extraction

        %% ---------------------- Phase 2 ----------------------
        %% Now, plugins are extracted, we can revisit the configuration
        %% because we have access to plugins' schemas.

        %% 6. Cuttlefish (pass #2, with plugin schemas)
        %% 7. Feature flags registry (including plugins)

        %% 8. Remaining environment variables -> configuration
        %% 9. Checking configuration
        %% 10. Checking+setting up distribution
        ok = rabbitmq_prelaunch_dist:setup(Context)
    catch
        _:{exit, Reason} ->
            remove_pid_file(Context),
            rabbitmq_prelaunch_helpers:exit(Reason)
    end;
run(_) ->
    ok.

write_pid_file(#{pid_file := PidFile}) ->
    Parent = filename:dirname(PidFile),
    case rabbitmq_prelaunch_helpers:mkdir_p(Parent) of
        ok ->
            OSPid = os:getpid(),
            file:write_file(PidFile, OSPid);
        Error ->
            Error
    end;
write_pid_file(_) ->
    ok.

remove_pid_file(#{pid_file := PidFile}) ->
    file:delete(PidFile);
remove_pid_file(_) ->
    ok.
