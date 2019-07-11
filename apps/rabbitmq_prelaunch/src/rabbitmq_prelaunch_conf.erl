-module(rabbitmq_prelaunch_conf).

-include_lib("kernel/include/file.hrl").
-include_lib("stdlib/include/zip.hrl").
-include_lib("rabbit_common/include/rabbit.hrl").

-export([setup/1]).

setup(Context) ->
    rabbit_log_prelaunch:debug(""),
    rabbit_log_prelaunch:debug("== Configuration =="),

    %% TODO: Should we call rabbit_config:validate_config_files/0 and
    %% adapt it to accept configuration file names as arguments?

    %% TODO: Check if directories/files are inside Mnesia dir.

    case find_actual_main_config_file(Context) of
        {MainConfigFile, erlang} ->
            load_erlang_term_based_config_file(MainConfigFile),
            ok;
        {MainConfigFile, cuttlefish} ->
            AdvancedConfigFile = find_actual_advanced_config_file(Context),
            load_cuttlefish_config_file(Context,
                                        MainConfigFile,
                                        AdvancedConfigFile),
            ok;
        undefined ->
            ok
    end.

find_actual_main_config_file(#{main_config_file_noex := FileNoEx}) ->
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

find_actual_advanced_config_file(#{advanced_config_file_noex := FileNoEx}) ->
    File = FileNoEx ++ ".config",
    case filelib:is_regular(File) of
        true  -> File;
        false -> undefined
    end.

load_erlang_term_based_config_file(ConfigFile) ->
    rabbit_log_prelaunch:debug(
      "Loading configuration file \"~s\" (Erlang terms based)", [ConfigFile]),
    case file:consult(ConfigFile) of
        {ok, [Config]} ->
            apply_erlang_term_based_config(Config);
        {ok, OtherTerms} ->
            rabbit_log_prelaunch:error(
              "Failed to load configuration file \"~s\", "
              "incorrect format: ~p",
              [ConfigFile, OtherTerms]),
            rabbitmq_prelaunch_helpers:exit(ex_config);
        {error, Reason} ->
            rabbit_log_prelaunch:error(
              "Failed to load configuration file \"~s\": ~s",
              [ConfigFile, file:format_error(Reason)]),
            rabbitmq_prelaunch_helpers:exit(ex_config)
    end.

load_cuttlefish_config_file(Context,
                            MainConfigFile,
                            AdvancedConfigFile) ->
    %% Load schemas.
    SchemaFiles = find_cuttlefish_schemas(Context),
    case SchemaFiles of
        [] ->
            rabbit_log_prelaunch:error(
              "No configuration schema found~n", []),
            rabbitmq_prelaunch_helpers:exit(ex_software);
        _ ->
            rabbit_log_prelaunch:debug(
              "Configuration schemas found:~n", []),
            [rabbit_log_prelaunch:debug("  - ~s", [SchemaFile])
             || SchemaFile <- SchemaFiles],
            ok
    end,
    Schema = cuttlefish_schema:files(SchemaFiles),

    %% Load configuration.
    rabbit_log_prelaunch:debug(
      "Loading configuration file \"~s\" (Cuttlefish based)",
      [MainConfigFile]),
    ConfigFiles = [MainConfigFile],
    Config0 = cuttlefish_conf:files(ConfigFiles),

    %% Finalize configuration, based on the schema.
    Config = case cuttlefish_generator:map(Schema, Config0) of
                 {error, Phase, {errorlist, Errors}} ->
                     %% TODO
                     rabbit_log_prelaunch:error(
                       "Error generating configuration in phase ~s:",
                       [Phase, Errors]),
                     [rabbit_log_prelaunch:error(
                        "  - ~s",
                        [cuttlefish_error:xlate(Error)])
                      || Error <- Errors],
                     rabbitmq_prelaunch_helpers:exit(ex_config);
                 ValidConfig ->
                     proplists:delete(vm_args, ValidConfig)
             end,

    %% Apply advanced configuration overrides, if any.
    Config1 = override_with_advanced_config(Config, AdvancedConfigFile),

    apply_erlang_term_based_config(Config1),
    ok.

find_cuttlefish_schemas(#{plugins_path := PluginsPath}) ->
    Plugins = rabbit_plugins:list(PluginsPath),
    rabbit_log_prelaunch:debug(
      "Looking up configuration schemas in RabbitMQ core and "
      "the following plugins:"),
    [rabbit_log_prelaunch:debug("  - ~s", [Plugin#plugin.name])
     || Plugin <- Plugins],
    find_cuttlefish_schemas(Plugins, []).

find_cuttlefish_schemas([Plugin | Rest], AllSchemas) ->
    Schemas = list_schemas_in_app(Plugin),
    find_cuttlefish_schemas(Rest, AllSchemas ++ Schemas);
find_cuttlefish_schemas([], AllSchemas) ->
    RabbitDir = code:lib_dir(rabbit),
    Schemas = list_schemas_in_app(RabbitDir),
    lists:sort(fun(A,B) -> A < B end, Schemas ++ AllSchemas).

list_schemas_in_app(#plugin{name = PluginName,
                            version = PluginVersion,
                            type = Type,
                            location = Location}) ->
    SchemaDir = case Type of
                    ez ->
                        PluginNameAndVersion = rabbit_misc:format(
                                                 "~s-~s",
                                                 [PluginName, PluginVersion]),
                        filename:join([Location,
                                       PluginNameAndVersion,
                                       "priv",
                                       "schema"]);
                    dir ->
                        filename:join([Location,
                                       "priv",
                                       "schema"])
                end,
    do_list_schemas_in_app(SchemaDir);
list_schemas_in_app(AppDir) when is_list(AppDir) ->
    SchemaDir = filename:join([AppDir, "priv", "schema"]),
    do_list_schemas_in_app(SchemaDir).

do_list_schemas_in_app(SchemaDir) ->
    case erl_prim_loader:list_dir(SchemaDir) of
        {ok, Files} ->
            [filename:join(SchemaDir, File)
             || [C | _] = File <- Files,
                C =/= $.
            ];
        error ->
            %% TODO
            []
    end.

override_with_advanced_config(Config, undefined) ->
    Config;
override_with_advanced_config(Config, AdvancedConfigFile) ->
    rabbit_log_prelaunch:debug(
      "Override with advanced configuration file \"~s\"", [AdvancedConfigFile]),
    case file:consult(AdvancedConfigFile) of
        {ok, [AdvancedConfig]} ->
            cuttlefish_advanced:overlay(Config, AdvancedConfig);
        {ok, OtherTerms} ->
            rabbit_log_prelaunch:error(
              "Failed to load advanced configuration file \"~s\", "
              "incorrect format: ~p",
              [AdvancedConfigFile, OtherTerms]),
            rabbitmq_prelaunch_helpers:exit(ex_config);
        {error, Reason} ->
            rabbit_log_prelaunch:error(
              "Failed to load advanced configuration file \"~s\": ~s",
              [AdvancedConfigFile, file:format_error(Reason)]),
            rabbitmq_prelaunch_helpers:exit(ex_config)
    end.

apply_erlang_term_based_config([{App, Vars} | Rest]) ->
    rabbit_log_prelaunch:debug(
      "Applying configuration for '~s': ~p",
      [App, Vars]),
    apply_app_env_vars(App, Vars),
    apply_erlang_term_based_config(Rest);
apply_erlang_term_based_config([]) ->
    ok.

apply_app_env_vars(App, [{Var, Value} | Rest]) ->
    ok = application:set_env(App, Var, Value, [{persistent, true}]),
    apply_app_env_vars(App, Rest);
apply_app_env_vars(_, []) ->
    ok.
