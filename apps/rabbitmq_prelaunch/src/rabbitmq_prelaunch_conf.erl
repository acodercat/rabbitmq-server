-module(rabbitmq_prelaunch_conf).

-export([setup/1]).

setup(Context) ->
    %% Environment variables (IN):
    %%
    %%   RABBITMQ_CONFIG_FILE
    %%     Main configuration file
    %%     Extension is optional. `.config` for the old rlang-term-based
    %%     format, `.conf` for the new Cuttlefish-based format.
    %%     Default: (Unix) ${SYS_PREFIX}/etc/rabbitmq/rabbitmq
    %%           (Windows) ${RABBITMQ_BASE}\rabbitmq
    %%
    %%   RABBITMQ_ADVANCED_CONFIG_FILE
    %%     Advanced configuration file
    %%     Erlang-term-based format with a `.config` extension.
    %%     Default: (Unix) ${SYS_PREFIX}/etc/rabbitmq/advanced.config
    %%           (Windows) ${RABBITMQ_BASE}\advanced.config
    %%
    %%   RABBITMQ_SCHEMA_DIR
    %%     Directory where all detected Cuttlefish schemas are written
    %%     Default: (Unix) ${SYS_PREFIX}/var/lib/rabbitmq/schema
    %%           (Windows) ${RABBITMQ_BASE}\schema
    %%
    %%   RABBITMQ_GENERATED_CONFIG_DIR
    %%     Directory where final configuration (generated from
    %%     Cuttlefish-based configuration) is written
    %%     Default: (Unix) ${SYS_PREFIX}/var/lib/rabbitmq/config
    %%           (Windows) ${RABBITMQ_BASE}\config

    ConfigBaseDir = get_config_base_dir(Context),
    MainConfigFileNoEx = get_main_config_file_noex(ConfigBaseDir),

    case find_actual_main_config_file(MainConfigFileNoEx) of
        {MainConfigFile, erlang} ->
            load_erlang_term_based_config_file(MainConfigFile),
            ok;
        {MainConfigFile, cuttlefish} ->
            AdvancedConfigFileNoEx = get_advanced_config_file_noex(
                                       ConfigBaseDir),
            AdvancedConfigFile = find_actual_advanced_config_file(
                                   AdvancedConfigFileNoEx),
            load_cuttlefish_config_file(Context,
                                        MainConfigFile,
                                        AdvancedConfigFile),
            ok;
        undefined ->
            ok
    end.

get_config_base_dir(#{os_type := {unix, _}}) ->
    SysPrefix = rabbitmq_prelaunch_helpers:get_sys_prefix(),
    filename:join([SysPrefix, "etc", "rabbitmq"]);
get_config_base_dir(#{os_type := {win32, _}}) ->
    rabbitmq_prelaunch_helpers:get_rabbitmq_base().

get_main_config_file_noex(ConfigBaseDir) ->
    File = rabbitmq_prelaunch_helpers:get_prefixed_env_var(
             "RABBITMQ_CONFIG_FILE",
             filename:join(ConfigBaseDir, "rabbitmq")),
    re:replace(File, "\\.(conf|config)$", "", [{return, list}]).

get_advanced_config_file_noex(ConfigBaseDir) ->
    File = rabbitmq_prelaunch_helpers:get_prefixed_env_var(
             "RABBITMQ_CONFIG_FILE",
             filename:join(ConfigBaseDir, "advanced")),
    re:replace(File, "\\.config$", "", [{return, list}]).

find_actual_main_config_file(FileNoEx) ->
    File1 = FileNoEx ++ ".conf",
    case filelib:is_regular(File1) of
        true ->
            {File1, cuttlefish};
        false ->
            File2 = FileNoEx ++ ".config",
            case filelib:is_regular(File2) of
                true  -> {File2, erlang};
                false -> undefined
            end
    end.

find_actual_advanced_config_file(FileNoEx) ->
    File = FileNoEx ++ ".config",
    case filelib:is_regular(File) of
        true  -> File;
        false -> undefined
    end.

load_erlang_term_based_config_file(ConfigFile) ->
    %% FIXME: See rabbit_config:update_app_config/1
    %% - Make sure applications are stopped
    %% - Use application_controller:change_application_data/2 (if documented)
    case file:consult(ConfigFile) of
        {ok, [Config]} ->
            do_load_erlang_term_based_config_file(Config);
        {error, Reason} ->
            io:format(standard_error,
                      "Failed to load configuration file \"~s\":~n~s~n",
                      [ConfigFile, file:format_error(Reason)]),
            rabbitmq_prelaunch_helpers:exit(ex_config)
    end.

do_load_erlang_term_based_config_file([{App, Vars} | Rest]) ->
    apply_app_env_vars(App, Vars),
    do_load_erlang_term_based_config_file(Rest);
do_load_erlang_term_based_config_file([]) ->
    ok.

apply_app_env_vars(App, [{Var, Value} | Rest]) ->
    ok = application:set_env(App, Var, Value, [{persistent, true}]),
    apply_app_env_vars(App, Rest);
apply_app_env_vars(_, []) ->
    ok.

load_cuttlefish_config_file(Context,
                            _MainConfigFileNoEx,
                            _AdvancedConfigFile) ->
    Schemas = find_cuttlefish_schemas(Context),
    ok.

find_cuttlefish_schemas(Context) ->
