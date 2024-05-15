####################################################################################
# Project automation.
#
# USAGE: `make clean bootstrap deploy test`
# 	- clean: tears down the k3d cluster and all apps
# 	- bootstrap: bootstraps the k3d cluster and cluster-auth
# 	- deploy: deploys all infrastructure and applications
# 	- test: runs all infrastructure and application tests
#
# NOTE: 
#   This project uses k8s-tools.git automation to dispatch commands 
#   into the containers described inside `k8s-tools.yml`. See the full 
#   docs here[1].  Summarizing calling conventions: targets written like
#   "▰/myservice/target_name" describe a callback so that container 
#   "myservice" will run "make .target_name".
#
# REF:
#   [1] https://github.com/elo-enterprises/k8s-tools#makefilecomposemk
####################################################################################

# BEGIN: Data & Macros
SHELL := bash
MAKEFLAGS += -s --warn-undefined-variables
.SHELLFLAGS := -euo pipefail -c
THIS_MAKEFILE := $(abspath $(firstword $(MAKEFILE_LIST)))
SRC_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null || pwd)
PROJECT_ROOT := $(shell dirname ${THIS_MAKEFILE})
export SRC_ROOT PROJECT_ROOT

# Override k8s-tools.yml service-defaults, 
# explicitly setting the k3d version used
export ALPINE_K8S_VERSION:=alpine/k8s:1.27.13
export K3D_VERSION:=v5.6.0
export KREW_PLUGINS=iexec popeye ktop doctor

# k3d cluster defaults, merged with whatever is in CLUSTER_CONFIG
export CLUSTER_NAME?=faas
export CLUSTER_CONFIG?=faas.cluster.k3d.yaml

# always use a local profile, ignoring whatever is in the parent environment
export KUBECONFIG:=./${CLUSTER_NAME}.profile.yaml

# NB: `FUNCTION_NAMESPACE` only used in older versions of fission?
# NB: `FISSION_CLI_VERSION` is not DRY with k8s-tools/fission container 
export KNATIVE_NAMESPACE_PREFIX := knative-
export KNS_VERSION:=v1.14.0
export KNE_VERSION:=v1.14.1
export FISSION_NAMESPACE?=fission
export FUNCTION_NAMESPACE=fission
export FISSION_CLI_VERSION?=v1.20.1
# ARGO_CLI_VERSION?=
export ARGO_NAMESPACE_PREFIX:=argo
export ARGO_WF_VERSION?=v3.5.4
export ARGO_EVENTS_URL:=https://raw.githubusercontent.com/argoproj/argo-events

# Creates dynamic targets from compose services 
# (See the docs at https://github.com/elo-enterprises/k8s-tools/)
include automation/Makefile.k8s.mk
include automation/Makefile.compose.mk
$(eval $(call compose.import, ▰, TRUE, ${PROJECT_ROOT}/k8s-tools.yml))

# setupdown/teardown automation for supported FaaS platforms
include automation/Makefile.argo.mk
include automation/Makefile.knative.mk
include automation/Makefile.fission.mk
include automation/Makefile.prometheus.mk
include automation/Makefile.cluster.mk

build: k8s-tools/__build__
	@# Only for dev & cache-busting (containers are pulled when they change)

top:
	cmd=ktop entrypoint=kubectl make k8s

ps: k3d.ps kubefwd.ps
	@#

cluster.stat: ▰/k8s/k8s.stat

clean: k8s-tools/__clean__ cluster.clean
bootstrap: docker.init cluster.bootstrap cluster.stat

test: argo.test fission.test 

bash: io.bash
shell: k8s-tools/k8s/shell
k9: k9s
panic: docker.panic
docs: 
	pynchon jinja render README.md.j2 \
	 && pynchon markdown preview README.md
