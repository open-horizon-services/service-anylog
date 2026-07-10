#!/bin/Makefile
$(info LOADING MAKEFILE)

# ──────────────────────────────────────────────
# Default values
# ──────────────────────────────────────────────
export IS_MANUAL      ?= false
export ANYLOG_TYPE    ?= anylog-generic
export TAG            ?= 2.0.2606
export IMAGE          ?= anylogco/anylog-network
export TEST_CONN      ?=
export LICENSE_KEY    ?=
export PROMPT_LICENSE ?= true

# OpenHorizon configs
export HZN_ORG_ID      ?= myorg
export HZN_LISTEN_IP   ?= 127.0.0.1
export SERVICE_VERSION ?= $(TAG)

# Resolve short-form aliases (operator → anylog-operator)
ifeq ($(ANYLOG_TYPE),$(filter $(ANYLOG_TYPE),generic master operator query publisher standalone-operator standalone-publisher))
    ANYLOG_TYPE := anylog-$(ANYLOG_TYPE)
    export ANYLOG_TYPE
endif

# Detect OS / architecture (still needed by OH scripts: env2json.sh, hzn commands)
export OS          := $(shell uname -s)
export UNAME_M     := $(shell uname -m)
export ANYLOG_UID  := $(shell id -u)
export ANYLOG_GID  := $(shell id -g)

ifeq ($(UNAME_M),x86_64)
	export DOCKER_PLATFORM := linux/amd64
else ifneq (,$(filter $(UNAME_M),aarch64 arm64))
	export DOCKER_PLATFORM := linux/arm64
else
	$(error Unsupported architecture: $(UNAME_M))
endif

# ARCH: prefer hzn if available, otherwise derive from uname
export ARCH := $(shell command -v hzn >/dev/null 2>&1 && hzn architecture || \
	( [ "$(UNAME_M)" = "x86_64" ] && echo "amd64" || echo "arm64" ))

# -------------------
# Load IMAGE / NODE_NAME / SERVICE_NAME from per-type config (used by OH targets)
# -------------------
ifneq ($(strip $(ANYLOG_TYPE)),)
    _SINGLE_FILE := docker-makefiles/$(ANYLOG_TYPE)/node_configs.env

    export NODE_NAME    := $(shell grep -m1 '^NODE_NAME=' "$(_SINGLE_FILE)" 2>/dev/null | cut -d= -f2- | tr -d '"\r')
    export SERVICE_NAME ?= $(NODE_NAME)
endif

# Generated OH policy files live alongside the .env, inside docker-makefiles/$(ANYLOG_TYPE)/
export POLICY_DIR := docker-makefiles/$(ANYLOG_TYPE)

# Needed by prep-build (docker pull/tag/push) — deploy.sh does its own detection for the docker lifecycle targets
export CONTAINER_CMD := $(shell command -v podman >/dev/null 2>&1 && echo "podman" || echo "docker")

# ──────────────────────────────────────────────
# Internal — build the flag string passed to deploy.sh
# ──────────────────────────────────────────────
_FLAGS := --type $(ANYLOG_TYPE) --tag $(TAG)
ifneq ($(IMAGE),anylogco/anylog-network)
    _FLAGS += --image $(IMAGE)
endif
ifeq ($(IS_MANUAL),true)
    _FLAGS += --manual
endif
ifneq ($(TEST_CONN),)
    _FLAGS += --test-conn $(TEST_CONN)
endif
ifeq ($(origin LICENSE_KEY),command line)
    _FLAGS += --license-key '$(LICENSE_KEY)'
endif
ifneq ($(filter true True TRUE 1 yes Yes YES,$(PROMPT_LICENSE)),)
    _FLAGS += --prompt-license
endif

ANYLOG_SH := bash deploy.sh

#========= prep configs =========
all: help

# Only used by the native OH targets below (deploy.sh does its own check internally)
check-configs:
	@if [ "$(IS_MANUAL)" != "true" ] && [ -z "$(ANYLOG_TYPE)" ]; then \
		echo "ERROR: Missing AnyLog type"; \
		$(MAKE) help; \
		exit 1; \
	elif [ "$(IS_MANUAL)" != "true" ] && [ ! -d docker-makefiles/$(ANYLOG_TYPE) ]; then \
		echo "ERROR: Missing directory for ANYLOG_TYPE=$(ANYLOG_TYPE)"; \
		$(MAKE) help; \
		exit 1; \
	fi

#========= Docker lifecycle (delegates to deploy.sh) =========
login: ## log into Docker Hub for AnyLog
	$(ANYLOG_SH) login $(_FLAGS)

pull: ## pull image from Docker Hub
	$(ANYLOG_SH) pull $(_FLAGS)

dry-run: ## generate docker-compose.yaml (or print docker-run cmd in manual mode)
	$(ANYLOG_SH) dry-run $(_FLAGS)

up: ## start AnyLog instance
	$(ANYLOG_SH) up $(_FLAGS)

down: ## stop AnyLog instance
	$(ANYLOG_SH) down $(_FLAGS)

clean: ## stop container and remove volumes
	$(ANYLOG_SH) clean $(_FLAGS)

clean-all: ## stop container, remove volumes and image
	$(ANYLOG_SH) clean-all $(_FLAGS)

logs: ## view container logs
	$(ANYLOG_SH) logs $(_FLAGS)

logs-f: ## follow container logs
	$(ANYLOG_SH) logs-f $(_FLAGS)

attach: ## attach to container (ctrl-d to detach)
	$(ANYLOG_SH) attach $(_FLAGS)

exec: ## attach to bash shell (anylog user)
	$(ANYLOG_SH) exec $(_FLAGS)

exec-root: ## attach to bash shell as root
	$(ANYLOG_SH) exec-root $(_FLAGS)

#========= testing (delegates to deploy.sh) =========
full-test: ## run test-status + test-node + test-network
	$(ANYLOG_SH) full-test $(_FLAGS)

test-status: ## execute `get status` against AnyLog node
	$(ANYLOG_SH) test-status $(_FLAGS)

test-node: ## execute `test node` against AnyLog node
	$(ANYLOG_SH) test-node $(_FLAGS)

test-network: ## execute `test network` against AnyLog node
	$(ANYLOG_SH) test-network $(_FLAGS)

check-processes: ## execute `get processes` against AnyLog node
	$(ANYLOG_SH) check-processes $(_FLAGS)

#========= Open Horizon commands (native — no docker-compose equivalent) =========
# TODO: Remove prep-build target once AnyLog releases use the proper Open Horizon
#       version format (#.#.####). At that point, pass TAG directly to full-deploy.
prep-build: check-configs ## [TEMPORARY] pull image under original TAG, retag to OH-compatible format, and push
	$(eval OH_VERSION := 1.0.$(shell date +%Y%m%d))
	@echo "Pulling $(IMAGE):$(TAG)..."
	$(CONTAINER_CMD) pull docker.io/$(IMAGE):$(TAG)
	@echo "Retagging → $(IMAGE):$(OH_VERSION)"
	$(CONTAINER_CMD) tag docker.io/$(IMAGE):$(TAG) docker.io/$(IMAGE):$(OH_VERSION)
	@echo "Pushing $(IMAGE):$(OH_VERSION)..."
	$(CONTAINER_CMD) push docker.io/$(IMAGE):$(OH_VERSION)
	@echo ""
	@echo "Image ready. Now run:"
	@echo "  make full-deploy ANYLOG_TYPE=$(ANYLOG_TYPE) TAG=$(OH_VERSION)"

license-check: check-configs ## resolve/prompt for LICENSE_KEY and write it into node_configs.env
	$(ANYLOG_SH) license-check $(_FLAGS)

prep-service: check-configs license-check ## generate service.definition.json, service.policy.json, service.deployment.json and node.policy.json
	@echo "Open Horizon Dry Run $(ANYLOG_TYPE) - $(NODE_NAME)"
	bash ./docker-makefiles/env2json.sh $(POLICY_DIR) . $(TAG)

full-deploy: prep-service publish-service publish-service-policy publish-deployment-policy agent-run ## deploy all services and policies, then start agent

deploy: prep-service publish-deployment-policy agent-run ## publish deployment and run agent

publish: prep-service publish-service publish-service-policy publish-deployment-policy ## publish services and policies

publish-version: prep-service publish-service publish-service-policy ## update version

publish-service: ## publish service
	@echo "=================="
	@echo "PUBLISHING SERVICE"
	@echo "=================="
	@hzn exchange service publish --org=$(HZN_ORG_ID) --user-pw=$(HZN_EXCHANGE_USER_AUTH) -O -P \
		--json-file=$(POLICY_DIR)/service.definition.json

publish-service-policy: ## publish service policy
	@echo "========================="
	@echo "PUBLISHING SERVICE POLICY"
	@echo "========================="
	@hzn exchange service addpolicy --org=$(HZN_ORG_ID) --user-pw=$(HZN_EXCHANGE_USER_AUTH) \
		-f $(POLICY_DIR)/service.policy.json \
		$(HZN_ORG_ID)/$(SERVICE_NAME)_$(SERVICE_VERSION)_$(ARCH)

publish-deployment-policy: prep-service ## publish deployment policy
	@echo "============================"
	@echo "PUBLISHING DEPLOYMENT POLICY"
	@echo "============================"
	@hzn exchange deployment addpolicy --org=$(HZN_ORG_ID) --user-pw=$(HZN_EXCHANGE_USER_AUTH) \
		-f $(POLICY_DIR)/service.deployment.json \
		$(HZN_ORG_ID)/policy-$(SERVICE_NAME)_$(SERVICE_VERSION)

agent-run: ## start agent
	@echo "================"
	@echo "REGISTERING NODE"
	@echo "================"
	@hzn register --name=hzn-client --policy=$(POLICY_DIR)/node.policy.json
	@watch $(MAKE) hzn-agreement-list

hzn-clean-all: unregister-agent remove-deployment-policy remove-service-policy remove-service ## unregister node, remove all policies/service, and wipe image+volumes

remove-service: ## remove service from hzn exchange
	@echo "=================="
	@echo "REMOVING SERVICE"
	@echo "=================="
	@hzn exchange service remove -f $(HZN_ORG_ID)/$(SERVICE_NAME)_$(SERVICE_VERSION)_$(ARCH)
	@echo ""

remove-service-policy: ## remove service policy from hzn exchange
	@echo "======================="
	@echo "REMOVING SERVICE POLICY"
	@echo "======================="
	@hzn exchange service removepolicy -f $(HZN_ORG_ID)/$(SERVICE_NAME)_$(SERVICE_VERSION)_$(ARCH)
	@echo ""

remove-deployment-policy: ## remove deployment policy from hzn exchange
	@echo "=========================="
	@echo "REMOVING DEPLOYMENT POLICY"
	@echo "=========================="
	@hzn exchange deployment removepolicy -f $(HZN_ORG_ID)/policy-$(SERVICE_NAME)_$(SERVICE_VERSION)
	@echo ""

unregister-agent: ## unregister agent(s) from OpenHorizon
	@echo "==================="
	@echo "UN-REGISTERING NODE"
	@echo "==================="
	@hzn unregister -f
	@echo ""

hzn-status: hzn-agreement-list hzn-event-list hzn-logs ## get a full summary of the logs

hzn-agreement-list: ## check agreement list
	@hzn agreement list

hzn-event-list: ## list event logs
	@echo "==========="
	@echo " EVENT LOG"
	@echo "==========="
	@hzn eventlog list

hzn-logs: ## view service logs
	@echo "========="
	@echo "SERVICE LOG"
	@echo "========="
	@hzn service log -f $(SERVICE_NAME)

deploy-check: ## check deployment (Open Horizon dry-run against generated policy files)
	@hzn deploycheck all -t device \
		-B $(POLICY_DIR)/service.deployment.json \
		--service=$(POLICY_DIR)/service.definition.json \
		--service-pol=$(POLICY_DIR)/service.policy.json \
		--node-pol=$(POLICY_DIR)/node.policy.json

#========= validate & help =========
check-vars: ## show resolved variable values (docker + OH)
	$(ANYLOG_SH) check-vars $(_FLAGS)
	@echo ""
	@echo "-- Open Horizon --"
	@echo "HZN_ORG_ID            Default: myorg                    Value: $(HZN_ORG_ID)"
	@echo "HZN_LISTEN_IP         Default: 127.0.0.1                Value: $(HZN_LISTEN_IP)"
	@echo "SERVICE_NAME                                            Value: $(SERVICE_NAME)"
	@echo "SERVICE_VERSION                                         Value: $(SERVICE_VERSION)"
	@echo "ARCH                                                    Value: $(ARCH)"
	@echo "POLICY_DIR                                              Value: $(POLICY_DIR)"

help:
	@echo "Usage: make [target] [VARIABLE=value]"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk -F':|##' '{ printf "  \033[36m%-24s\033[0m %s\n", $$1, $$3 }'
	@echo ""
	@echo "Common variables you can override:"
	@echo "  IS_MANUAL           Use docker run instead of docker compose (default: false)"
	@echo "  ANYLOG_TYPE         Type of node to deploy (generic, master, operator, query, publisher,"
	@echo "                      standalone-operator, standalone-publisher)"
	@echo "  IMAGE               Docker image repo"
	@echo "  TAG                 Docker image tag"
	@echo "  LICENSE_KEY         AnyLog license key"
	@echo "  PROMPT_LICENSE      Prompt if no saved license (default: true)"
	@echo "  TEST_CONN           REST connection info for test-node / test-network"
	@echo "  HZN_ORG_ID          Open Horizon exchange org"
	@echo "  HZN_LISTEN_IP       Open Horizon listen IP"
	@echo ""
	@echo "Without make:"
	@echo "  bash deploy.sh help"
	@echo ""

.PHONY: all check-configs license-check \
        login pull dry-run up down clean clean-all \
        logs logs-f attach exec exec-root \
        full-test test-status test-node test-network check-processes \
        prep-build prep-service full-deploy deploy publish publish-version \
        publish-service publish-service-policy publish-deployment-policy \
        agent-run hzn-clean-all remove-service remove-service-policy \
        remove-deployment-policy unregister-agent hzn-status hzn-agreement-list \
        hzn-event-list hzn-logs deploy-check \
        check-vars help