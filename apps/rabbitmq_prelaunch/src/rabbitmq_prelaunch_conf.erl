-module(rabbitmq_prelaunch_conf).

-include_lib("kernel/include/file.hrl").
-include_lib("stdlib/include/zip.hrl").
-include_lib("rabbit_common/include/rabbit.hrl").

-export([setup/1]).

setup(Context) ->
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
    io:format(standard_error, "Calling Cuttlefish with schemas:~n~p~n", [Schemas]),
    ok.

find_cuttlefish_schemas(#{plugins_path := PluginsPath}) ->
    Plugins = rabbit_plugins:list(PluginsPath),
    find_cuttlefish_schemas(Plugins, []).

find_cuttlefish_schemas([Plugin | Rest], AllSchemas) ->
    Schemas = list_schemas_in_app(Plugin),
    find_cuttlefish_schemas(Rest, AllSchemas ++ Schemas);
find_cuttlefish_schemas([], AllSchemas) ->
    RabbitDir = code:lib_dir(rabbit),
    Schemas = list_schemas_in_app(RabbitDir),
    Schemas ++ AllSchemas.

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
