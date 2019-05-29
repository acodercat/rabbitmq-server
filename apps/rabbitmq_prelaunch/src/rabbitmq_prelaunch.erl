-module(rabbitmq_prelaunch).

-export([run/0]).

run() ->
    ok = run(node()),
    ignore.

run(nonode@nohost) ->
    %% Stop Mnesia now. It is started because `rabbit` depends on it
    %% (and this `rabbitmq_prelaunch` too). But because distribution
    %% is not configured yet at the time it is started, it is
    %% non-functionnal. We can stop it now, setup distribution and
    %% `rabbit` will take care of starting it again.
    mnesia:stop(),

    %% TODO: Add a small logging facility to log warnings and errors,
    %% and help debug this application before the actual logger is
    %% ready.
    %%
    %% It could be something which wraps the final logger and writes to
    %% stderr before it is ready.

    %% Prepare some informations required during setup.
    OSType = os:type(),
    NameType = rabbitmq_prelaunch_helpers:get_node_name_type(),
    Nodename = rabbitmq_prelaunch_helpers:get_node_name(NameType),
    ConfigBaseDir = ,
    MnesiaBaseDir = ,
    Context = #{os_type => OSType,
                nodename => Nodename,
                nodename_type => NameType},

    %% 1. Write PID file
    PidFile = get_pid_file_path(Context),
    ok = write_pid_file(PidFile),

    %% If one step fails, we remove the PID file and exit with the
    %% provided status code.
    try
        %% ---------------------- Phase 1 ----------------------
        %% Here, we do the minimum to be ready for the next phase.
        %% Basically we need the main configuration to know:
        %%     - paths to log files
        %%     - where to exract plugins
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
            remove_pid_file(PidFile),
            rabbitmq_prelaunch_helpers:exit(Reason)
    end;
run(_) ->
    ok.

get_pid_file_path(#{os_type := {win32, _}}) ->
    %% Environment variables (IN):
    %%
    %%   RABBITMQ_PID_FILE
    %%     PID file
    %%     Default: (Unix) ${SYS_PREFIX}/etc/rabbitmq/rabbitmq
    %%           (Windows) <none>
    undefined;
get_pid_file_path(_) ->
    rabbitmq_prelaunch_helpers:get_prefixed_env_var(
      "RABBITMQ_PID_FILE",
      rabbitmq_prelaunch_helpers:get_prefixed_env_var("RABBIT)).

write_pid_file(PidFile) ->
    ok.

remove_pid_file(PidFile) ->
    ok.
