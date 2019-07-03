PROJECT = rabbitmq_prelaunch
PROJECT_DESCRIPTION = RabbitMQ prelaunch procedure
PROJECT_VERSION = 0.1.0

LOCAL_DEPS = mnesia
DEPS = rabbit_common lager cuttlefish

#dep_cuttlefish = hex 2.1.4
dep_cuttlefish = git https://github.com/rabbitmq/cuttlefish.git read-files-from-ez-archives

include ../../rabbitmq-components.mk
include ../../erlang.mk

LAGER_EXTRA_SINKS += rabbit_log_prelaunch

lager_extra_sinks = $(subst $(space),$(comma),$(LAGER_EXTRA_SINKS))
LAGER_ERLC_OPTS += +'{parse_transform,lager_transform}' \
		   +'{lager_extra_sinks,[$(lager_extra_sinks)]}'

ERLC_OPTS += $(LAGER_ERLC_OPTS)
