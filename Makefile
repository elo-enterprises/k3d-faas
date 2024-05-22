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

# Creates dynamic targets from compose services (See REF[1])
include Makefile.k8s.mk
include Makefile.compose.mk
$(eval $(call compose.import, ▰, TRUE, ${PROJECT_ROOT}/k8s-tools.yml))

# END: Data & Macros
####################################################################################
# BEGIN: Top-level:: These are the main entrypoints that you probably want.

# Only for dev & cache-busting (containers are pulled when they change)
build: k8s-tools/__build__

project.show: show 
show: ▰/base/self.show
self.show:
	@#
	env|grep CLUSTER 
	env|grep KUBE 
	env|grep DOCKER
	set -x \
	&& kubectl cluster-info \
	&& kubectl get nodes \
	&& kubectl get namespace

clean: k8s-tools/__clean__ cluster.clean
bootstrap: docker.init cluster.bootstrap project.show

deploy: deploy.fission deploy.argo #deploy.knative
deploy.fission: fission.infra.setup fission.app.setup
deploy.argo: argo.infra.setup argo.app.setup
deploy.knative: knative.infra.setup 

test: test.fission test.argo 
test.fission: cluster.wait fission.infra.test fission.app.test
test.argo: cluster.wait argo.infra.test argo.test_app
test.knative: cluster.wait knative.infra.test knative_app.test

# END: Top-level
####################################################################################
# BEGIN: Cluster-ops:: These targets use the `k3d` container

cluster.shell: k8s.shell/default/test-harness
cluster.clean: ▰/k3d/self.cluster.clean
cluster.test: ▰/k3d/self.cluster.test
cluster.wait: ▰/base/k8s.pods.wait_until_ready
cluster.bootstrap: \
	▰/k3d/self.registries.setup \
	▰/k3d/self.cluster.setup \
	▰/k3d/self.cluster.auth \
	cluster.wait \
	cluster.test

##### User-facing targets ##########################################################
fission.show: ▰/base/self.fission.app.show
fission.infra.setup: ▰/base/self.fission.infra.setup project.show 
fission.infra.teardown: ▰/base/self.fission.infra.teardown
fission.infra.test: ▰/fission/self.fission.infra.test
fission.app.setup: fission.infra.test ▰/fission/self.fission.app.deploy
fission.app.test: ▰/fission/self.fission.app.test

knative.infra.setup: ▰/base/self.knative.infra.setup
knative.infra.teardown: ▰/base/self.knative.infra.teardown
knative.infra.test: ▰/kn/self.knative.infra.test
knative_app.setup: ▰/kn/self.knative.app.setup
knative_app.test: ▰/kn/self.knative.app.test

argo.shell: k8s.shell/argo/test-harness
argo.infra.setup: \
	▰/base/self.argo.workflows \
	▰/base/self.argo.events 
argo.infra.teardown: ▰/base/self.argo.teardown
argo.infra.test: \
	▰/base/self.argo.test_harness \
	▰/base/self.argo.test_webhook
argo.infra.expose: ▰/kubefwd/argo.expose
argo.app.setup: ▰/argo/self.argo.app.setup
argo.app.test: ▰/argo/self.argo.app.test


##### Private targets (these run inside containers) ###########################
self.cluster.test:
	make k8s.test_pod_in_namespace/default/test-harness
self.cluster.clean:
	set -x && k3d cluster delete $${CLUSTER_NAME}
self.registries.setup: self.registries.dockerio  self.registries.quayio 
self.registries.quayio:
self.registries.dockerio:
	k3d registry ls | grep docker-io \
	|| k3d registry create \
		docker-io -p 5000 \
		--proxy-remote-url https://registry-1.docker.io \
		-v ~/.local/share/docker-io-registry:/var/lib/registry
# Disabled, since current k3d supports multiple registries, but only uses the first 
#k3d registry ls | grep quay-io \
#|| k3d registry create \
#	quay-io -p 5001 \
#	--proxy-remote-url https://quay.io \
#	-v ~/.local/share/quay-io-registry:/var/lib/registry
self.cluster.setup:
	@# Setup for the K3d cluster
	set -x \
	&& k3d --version \
	&& k3d cluster list | grep $${CLUSTER_NAME} \
	|| k3d cluster create \
		--config $${CLUSTER_CONFIG} \
		--registry-use k3d-docker-io:5000 \
		--registry-config faas.registries.k3d.yml \
		--volume $$(pwd)/:/$${CLUSTER_NAME}@all \
		--wait
self.cluster.auth:
	@# Setup authentication for the cluster
	@# NB: The KUBECONFIG here is already project-local;
	@# we ignore whatever is coming from the parent environment
	rmdir $${KUBECONFIG} 2>/dev/null || rm -f $${KUBECONFIG}
	set -x && k3d kubeconfig merge $${CLUSTER_NAME} --output $${KUBECONFIG}

# END: Cluster-ops
####################################################################################
# BEGIN: Fission Infra/Apps :: 
#   Infra uses `kubectl` container, but apps require the `fission` container for CLI
#   - https://fission.io/docs/installation/
#   - https://fission.io/docs/reference/fission-cli/fission_token_create/

self.fission.infra.setup: k8s.namespace.create/$${FISSION_NAMESPACE}
	kubectl create -k "github.com/fission/fission/crds/v1?ref=v1.20.1" || true
	kubectl config set-context --current --namespace=$$FISSION_NAMESPACE
	kubectl apply -f \
		https://github.com/fission/fission/releases/download/${FISSION_CLI_VERSION}/fission-all-${FISSION_CLI_VERSION}-minikube.yaml
	kubectl config set-context --current --namespace=default
	make k8s.namespace.wait/fission k8s.namespace.wait/default
self.fission.infra.teardown: k8s.namespace.purge/$${FISSION_NAMESPACE}
self.fission.infra.test: 
	set -x && fission version && fission check
self.fission.app.show: k8s.kubens/fission
	kubectl get po
	kubectl get svc 
self.fission.app.deploy: k8s.kubens/default
	( fission env list | grep fission/python-env ) \
		|| fission env create --name python --image fission/python-env
self.fission.app.test: k8s.kubens/default
	make k8s.namespace.wait/$${FISSION_NAMESPACE} k8s.namespace.wait/default 
	set -x && echo FUNCTION_NAMESPACE=$${FUNCTION_NAMESPACE} && (fission function list | grep fission-app) \
		|| fission function create --name fission-app --env python --code src/fission/app.py \
	&& fission function test --timeout=0 --name fission-app


# END: Fission infra/apps
####################################################################################
# BEGIN: Knative Infra / Apps ::
#   Dispatching to `kubectl` container and `kn` container for the the `kn` and `func` CLI
#   - https://knative.run/article/How_to_deploy_a_Knative_function_on_Kubernetes.html
#   - https://knative.dev/docs/getting-started/first-service/
#   - https://knative.dev/docs/samples/

self.knative.infra.setup: #.knative.infra.operator .knative.infra.serving
	kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNS_VERSION}/serving-crds.yaml
	kubectl apply -f https://github.com/knative/serving/releases/download/knative-${KNS_VERSION}/serving-core.yaml
	kubectl apply -f https://github.com/knative/eventing/releases/download/knative-${KNE_VERSION}/eventing-crds.yaml
	kubectl apply -f https://github.com/knative/eventing/releases/download/knative-${KNE_VERSION}/eventing-core.yaml
	kubectl get pods -n knative-eventing
self.knative.infra.teardown: k8s.purge_namespaces_by_prefix/knative
self.knative.infra.test: k8s.kubens/knative-serving
	func version
	kn version
	kubectl get pods
	cd src/knf/; tree
self.knative.app.setup:
	echo app-placeholder
.knative.app.teardown: 
	echo test-placeholder
self.knative.app.test:
	echo test-placeholder

# END: Knative infra/apps
####################################################################################
# BEGIN: shortcuts and aliases
bash: compose.bash
shell: k8s-tools/base/shell
k9: k9s
panic: docker.panic
docs: 
	pynchon jinja render README.md.j2 \
	 && pynchon markdown preview README.md
vhs:
	rm -f img/*.gif 
	ls img/*.tape | xargs -n1 -I% bash -x -c "vhs %"
	firefox img/*gif

# END: shortcuts and aliases
####################################################################################
# https://argoproj.github.io/argo-events/quick_start/
# FIXME: pin versions
#
self.argo.workflows: k8s.kubens.create/argo
	kubectl apply -f https://github.com/argoproj/argo-workflows/releases/download/${ARGO_WF_VERSION}/install.yaml
self.argo.events: k8s.kubens.create/argo-events
	kubectl apply -f ${ARGO_EVENTS_URL}/stable/manifests/install.yaml
	kubectl apply -n argo-events -f src/argo/eventbus.native.yaml
	kubectl apply -n argo-events -f src/argo/event-sources.webhook.yaml
	kubectl apply -n argo-events -f ${ARGO_EVENTS_URL}/6a44acd1ac57a52/examples/rbac/sensor-rbac.yaml
	kubectl apply -n argo-events -f ${ARGO_EVENTS_URL}/6a44acd1ac57a52/examples/rbac/workflow-rbac.yaml
	kubectl apply -n argo-events -f src/argo/webhook.sensor.yaml
self.argo.teardown: k8s.purge_namespaces_by_prefix/$${ARGO_NAMESPACE_PREFIX}
self.argo.expose: k8s.kubens/argo-events
	kubefwd svc -v -f metadata.name=webhook-eventsource-svc
self.argo.test_harness: k8s.test_pod_in_namespace/argo-events/test-harness
self.argo.svc_ip: 
	printf "Looking for svc ip\n" > /dev/stderr \
	&& kubectl get svc \
		webhook-eventsource-svc \
		-o json \
		| tee /dev/stderr | jq -r .spec.clusterIP
self.argo.svc_port: 
	printf "Looking for svc port\n" > /dev/stderr \
	&& kubectl get svc \
		webhook-eventsource-svc \
		-o json \
		| tee /dev/stderr | jq -r .spec.ports[0].port
self.argo.test_webhook: k8s.kubens/argo-events
	export ip=`make .self.argo.svc_ip` \
	&& export port=`make .self.argo.svc_port` \
	&& set -x && kubectl exec -i \
		test-harness -- /bin/bash -c "curl -s \
			-d '{\"message\":\"this is my first webhook\"}' \
			-H \"Content-Type: application/json\" \
			-X POST http://$${ip}:$${port}/example"
self.argo.app.setup: k8s.kubens/argo-events
self.argo.app.test: k8s.kubens/argo-events
	kubectl get po
	kubectl get svc
	argo version
	kubectl -n argo-events get workflows | grep "webhook"
	argo list | grep webhook
	argo get @latest