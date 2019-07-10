-module(rabbitmq_prelaunch_cluster).

-export([setup/1]).

setup(_Context) ->
    rabbit_log_prelaunch:debug(""),
    rabbit_log_prelaunch:debug("== Clustering =="),
    rabbit_log_prelaunch:debug("Preparing cluster status files"),
    rabbit_node_monitor:prepare_cluster_status_files(),
    rabbit_log_prelaunch:debug("Upgrading Mnesia schema"),
    ok = rabbit_upgrade:maybe_upgrade_mnesia(),
    %% It's important that the consistency check happens after
    %% the upgrade, since if we are a secondary node the
    %% primary node will have forgotten us
    rabbit_log_prelaunch:debug("Checking cluster consistency"),
    rabbit_mnesia:check_cluster_consistency(),
    ok.
