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
#   "myservice" will run "make ↪target_name".
#
# REF:
#   [1] https://github.com/elo-enterprises/k8s-tools#makefilecomposemk
####################################################################################

# BEGIN: Data & Macros
SHELL := bash
MAKEFLAGS += -s --warn-undefined-variables
.SHELLFLAGS := -euo pipefail -c
THIS_MAKEFILE := $(abspath $(firstword $(MAKEFILE_LIST)))
THIS_MAKEFILE := `python -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' ${THIS_MAKEFILE}`

SRC_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null || pwd)
PROJECT_ROOT := $(shell dirname ${THIS_MAKEFILE})
export SRC_ROOT PROJECT_ROOT

# k3d cluster defaults, merged with whatever is in CLUSTER_CONFIG
export CLUSTER_NAME?=faas
export CLUSTER_CONFIG?=faas.cluster.k3d.yaml

# always use a local profile, ignoring whatever is in the parent environment
export KUBECONFIG:=./${CLUSTER_NAME}.profile.yaml


# Creates dynamic targets from compose services (See REF[1])
include Makefile.compose.mk
$(eval $(call compose.import, ▰, ↪, TRUE, ${PROJECT_ROOT}/k8s-tools.yml))
# $(eval $(call compose.import, ▰, ↪, TRUE, ${PROJECT_ROOT}/docker-compose.yml))

# END: Data & Macros
####################################################################################
# BEGIN: Top-level:: These are the main entrypoints that you probably want.

# build: 
# 	@# Not used from automation, containers are pulled when they change
# 	docker compose -f k8s-tools.yml build



project.show: ▰/base/show
↪show:
	@#
	echo CLUSTER_NAME=$${CLUSTER_NAME}
	echo KUBECONFIG=$${KUBECONFIG}
	kubectl cluster-info
	kubectl get nodes
	kubectl get namespace

clean: this_cluster.clean compose.clean
bootstrap: docker.init compose.init this_cluster.bootstrap project.show

deploy: deploy.fission deploy.argo #deploy.knative
deploy.fission: fission_infra.setup fission_app.setup
deploy.argo: argo_infra.setup
deploy.knative: knative_infra.setup 
deploy.apps: fission_app.setup 
# fission_app.setup 
# deploy.apps: knative_app.setup

test: ▰/base/k8s.namespace.wait/all fission_infra.test fission_app.test 
# test: knative_infra.test knative_app.test
# test: argo_infra.test argo.test_app

# END: Top-level
####################################################################################
# BEGIN: Cluster-ops:: These targets use the `k3d` container

this_cluster.clean: ▰/k3d/this.clean
this_cluster.bootstrap: ▰/k3d/this.setup ▰/k3d/this.auth ▰/base/this.wait
↪this.wait: k8s.pods.wait_until_ready
↪this.clean:
	k3d cluster delete $${CLUSTER_NAME}
↪this.setup:
	set -x \
	&& k3d --version && (k3d cluster list | grep $${CLUSTER_NAME} ) \
	|| k3d cluster create \
		--config $${CLUSTER_CONFIG} \
		--api-port 6551 \
		--port 8080:80@loadbalancer \
		--volume $(pwd)/:/$${CLUSTER_NAME}@all \
		--wait
↪this.auth:
	rmdir $${KUBECONFIG} 2>/dev/null || rm -f $${KUBECONFIG}
	k3d kubeconfig merge $${CLUSTER_NAME} --output $${KUBECONFIG}

# END: Cluster-ops
####################################################################################
# BEGIN: Fission Infra/Apps :: 
#   Infra uses `kubectl` container, but apps require the `fission` container for CLI
#   - https://fission.io/docs/installation/
#   - https://fission.io/docs/reference/fission-cli/fission_token_create/

export FISSION_NAMESPACE?=fission

# NB: only used in older versions of fission?
export FUNCTION_NAMESPACE=fission

# NB: version is not DRY with k8s-tools/fission container 
export FISSION_VERSION?=v1.20.1

fission.show: ▰/base/fission.show
↪fission.show:
	kubens fission 
	kubectl get po
	kubectl get svc 
	kubens -
fission_infra.setup: ▰/base/reactor.setup project.show 
fission_infra.teardown: ▰/base/reactor.teardown
fission_infra.test: ▰/fission/reactor.test
↪reactor.setup: k8s.namespace.create/$${FISSION_NAMESPACE}
	kubectl create -k "github.com/fission/fission/crds/v1?ref=v1.20.1" || true
	kubectl config set-context --current --namespace=$$FISSION_NAMESPACE
	kubectl apply -f https://github.com/fission/fission/releases/download/v1.20.1/fission-all-v1.20.1-minikube.yaml
	kubectl config set-context --current --namespace=default #to change context to default namespace after installation
	make k8s.namespace.wait/fission k8s.namespace.wait/default
↪reactor.teardown: k8s.namespace.purge/$${FISSION_NAMESPACE}
↪reactor.test: #fission_infra.auth
	set -x \
	&& fission version \
	&& fission check
fission_app.setup: fission_infra.test ▰/fission/fission_app.deploy
fission_app.test: ▰/fission/fission_app.test
↪fission_app.deploy: k8s.kubens/default
	( fission env list | grep fission/python-env ) \
		|| fission env create --name python --image fission/python-env
↪fission_app.test: k8s.kubens/default
	@#
	make k8s.namespace.wait/$${FISSION_NAMESPACE} k8s.namespace.wait/default 
	set -x && echo $$FUNCTION_NAMESPACE && (fission function list | grep fission-app) \
		|| fission function create --name fission-app --env python --code src/fission/app.py \
	&& fission function test --timeout=0 --name fission-app


# END: Fission infra/apps
####################################################################################
# BEGIN: Knative Infra / Apps ::
#   Dispatching to `kubectl` container and `kn` container for the the `kn` and `func` CLI
#   - https://knative.run/article/How_to_deploy_a_Knative_function_on_Kubernetes.html
#   - https://knative.dev/docs/getting-started/first-service/
#   - https://knative.dev/docs/samples/
export KNATIVE_NAMESPACE_PREFIX := knative-
export KNS_VERSION:=v1.14.0
export KNE_VERSION:=v1.14.1

knative: knative_infra.teardown knative_infra.setup knative_app.setup
knative_infra.setup: ▰/base/self.setup_infra
knative_infra.teardown: ▰/base/self.teardown_infra
knative_infra.test: ▰/kn/self.test_infra
↪self.setup_infra: #↪knative_infra.operator ↪knative_infra.serving
	kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNS_VERSION}/serving-crds.yaml
	kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNS_VERSION}/serving-core.yaml
	kubectl apply -f https://github.com/knative/eventing/releases/download/knative-${KNE_VERSION}/eventing-crds.yaml
	kubectl apply -f https://github.com/knative/eventing/releases/download/knative-${KNE_VERSION}/eventing-core.yaml
	kubectl get pods -n knative-eventing
↪self.teardown_infra: k8s.purge_namespaces_by_prefix/knative
↪self.test_infra: k8s.kubens/knative-serving
	func version
	kn version
	kubectl get pods
	cd src/knf/; tree
knative_app.setup: ▰/kn/self.setup_app
knative_app.test: ▰/kn/self.test_app
↪self.setup_app:
	echo app-placeholder
↪self.test_app:
	echo test-placeholder
↪self.teardown_app: 
	echo test-placeholder

# END: Knative infra/apps
####################################################################################
# BEGIN: shortcuts and aliases
bash: compose.bash
shell: k8s-tools/base/shell
k9: k9s
panic: docker.panic
docs:
	pynchon jinja render README.md.j2

# END: shortcuts and aliases
####################################################################################
# https://argoproj.github.io/argo-events/quick_start/
export ARGO_NAMESPACE_PREFIX:=argo
export ARGO_WF_VERSION?=v3.5.4
export ARGO_EVENTS_URL:=https://raw.githubusercontent.com/argoproj/argo-events

# argo: argo_infra argo_app

# argo_infra: argo_infra.teardown argo_infra.setup compose.wait/60 argo_infra.test
# zzz: #▰/base/bonk
# 	cmd="exec -n default -it shell -- sh" make kubectl 

# ↪bonk:
# 	make k8s.shell/default
k8s.shell/%:
	@# Usage: k8s.shell/<namespace>/<pod>
	@# WARNING: Target assumes that k8s-tools.yml is imported to the root namespace, 
	@# w/ default syntax.  This target MUST run from the host + also uses containers.
	$(eval export namespace:=$(shell echo ${*}|awk -F/ '{print $$1}')) \
	$(eval export pod_name:=$(shell echo ${*}|awk -F/ '{print $$2}')) \
	make ▰/base/k8s.test_pod_in_namespace/$${namespace}/$${pod_name}/$${pod_image:-debian}
	printf "${COLOR_GREEN}${COLOR_DIM}k8s.shell // ${NO_COLOR}${COLOR_GREEN}$${namespace}${COLOR_DIM} // ${NO_COLOR}${COLOR_GREEN}$${pod_name}${NO_COLOR} :: \n" > /dev/stderr \
	&& set -x \
	&& cmd="exec -n $${namespace} -it ${pod_name} -- bash" make kubectl 

# 	&& make k8s.namespace/$${namespace}

argo.shell: \
	k8s.shell/argo/test-harness

argo_infra.setup: ▰/base/argo.workflows ▰/base/argo.events 
argo_infra.teardown: ▰/base/argo.teardown
argo_infra.test: ▰/base/argo.test_harness ▰/base/argo.test_webhook
argo_infra.expose: ▰/kubefwd/argo.expose
argo_app: ▰/argo/argo.setup_app
argo_app.test: ▰/argo/argo.test_app
↪argo.workflows: k8s.kubens.create/argo
	kubectl apply -f https://github.com/argoproj/argo-workflows/releases/download/${ARGO_WF_VERSION}/install.yaml
# FIXME: pin versions
↪argo.events: k8s.kubens.create/argo-events
	kubectl apply -f ${ARGO_EVENTS_URL}/stable/manifests/install.yaml
	kubectl apply -n argo-events -f src/argo/eventbus.native.yaml
	kubectl apply -n argo-events -f src/argo/event-sources.webhook.yaml
	kubectl apply -n argo-events -f ${ARGO_EVENTS_URL}/6a44acd1ac57a52/examples/rbac/sensor-rbac.yaml
	kubectl apply -n argo-events -f ${ARGO_EVENTS_URL}/6a44acd1ac57a52/examples/rbac/workflow-rbac.yaml
	kubectl apply -n argo-events -f src/argo/webhook.sensor.yaml
↪argo.teardown: k8s.purge_namespaces_by_prefix/$${ARGO_NAMESPACE_PREFIX}
↪argo.expose: k8s.kubens/argo-events
	kubefwd svc -v -f metadata.name=webhook-eventsource-svc
↪argo.test_harness: k8s.kubens/argo-events
	export pod_image="alpine/k8s:1.30.0" pod_name=test-harness \
	&& kubectl delete pod $${pod_name} --now --wait || true \
	&& namespace=`kubens -c` make k8s.test_pod.in_namespace \
	&& set -x \
	&& kubectl wait --for=condition=Ready pod/$${pod_name} --timeout=999s
↪argo.svc_ip: 
	printf "Looking for svc ip\n" > /dev/stderr \
	&& kubectl get svc \
		webhook-eventsource-svc \
		-o json \
		| tee /dev/stderr | jq -r .spec.clusterIP
↪argo.svc_port: 
	printf "Looking for svc port\n" > /dev/stderr \
	&& kubectl get svc \
		webhook-eventsource-svc \
		-o json \
		| tee /dev/stderr | jq -r .spec.ports[0].port

↪argo.test_webhook: k8s.kubens/argo-events
	export ip=`make ↪argo.svc_ip` \
	&& export port=`make ↪argo.svc_port` \
	&& set -x && kubectl exec -i \
		test-harness -- /bin/bash -c "curl -s \
			-d '{\"message\":\"this is my first webhook\"}' \
			-H \"Content-Type: application/json\" \
			-X POST http://$${ip}:$${port}/example"
↪argo.setup_app: k8s.kubens/argo-events
↪argo.test_app: k8s.kubens/argo-events
	kubectl get po
	kubectl get svc
	argo version
	kubectl -n argo-events get workflows | grep "webhook"
	argo list | grep webhook
	argo get @latest