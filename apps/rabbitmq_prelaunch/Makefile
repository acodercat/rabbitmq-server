PROJECT = rabbitmq_prelaunch
PROJECT_DESCRIPTION = RabbitMQ prelaunch procedure
PROJECT_VERSION = 0.1.0

LOCAL_DEPS = mnesia
DEPS = rabbit_common lager cuttlefish

#dep_cuttlefish = hex 2.1.4
dep_cuttlefish = git https://github.com/rabbitmq/cuttlefish.git read-files-from-ez-archives

include ../../rabbitmq-components.mk
include ../../erlang.mk
