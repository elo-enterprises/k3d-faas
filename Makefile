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
export CLUSTER_AGENT_COUNT?=10
export CLUSTER_CONFIG?=faas.cluster.k3d.yaml

# always use a local profile, ignoring whatever is in the parent environment
export KUBECONFIG:=./${CLUSTER_NAME}.profile.yaml


# Creates dynamic targets from compose services (See REF[1])
include Makefile.compose.mk
$(eval $(call compose.import, ▰, ↪, TRUE, ${PROJECT_ROOT}/k8s-tools.yml))
#$(eval $(call compose.import, ▰, ↪, TRUE, ${PROJECT_ROOT}/docker-compose.yml))

# END: Data & Macros
####################################################################################
# BEGIN: Top-level:: These are the main entrypoints that you probably want.

build: 
	@# Not used from automation, containers are pulled when they change
	docker compose -f k8s-tools.yml build
# project.registry:
# 	set -x && k3d registry list|grep k3d-docker-io \
# 	|| k3d registry create docker-io \
# 		-p 3000 \
# 		--proxy-remote-url https://registry-1.docker.io \
# 		-v ~/.local/share/docker-io-registry:/var/lib/registry
# 	# docker compose -f k8s-tools.yml stop -t 1 docker-registry 
# 	# docker compose -f k8s-tools.yml up -d docker-registry 
# 	# make compose.wait/10
# 	# curl -u docker:docker http://localhost:3000/v2
# 	# # docker pull distribution/registry:master
# 	# curl -u docker:docker http://localhost:3000/v2/_catalog
# project.registry.list:

k9s/%:
	make k9s cmd="-n ${*}"

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

test: this_cluster.wait fission_infra.test fission_app.test 
# test: knative_infra.test knative_app.test
# test: argo_infra.test argo_app.test

# END: Top-level
####################################################################################
# BEGIN: Cluster-ops:: These targets use the `k3d` container

this_cluster.bootstrap: ▰/k3d/this_cluster.setup ▰/k3d/this_cluster.auth ▰/base/this_cluster.wait
this_cluster.wait: ▰/base/this_cluster.wait
this_cluster.clean: ▰/k3d/this_cluster.clean
↪this_cluster.clean:
	k3d cluster delete $${CLUSTER_NAME}
↪this_cluster.setup:
	set -x \
	&& k3d --version && (k3d cluster list | grep $${CLUSTER_NAME} ) \
	|| k3d cluster create \
		--config $${CLUSTER_CONFIG} \
		--api-port 6551 --servers 3 \
		--agents 6 \
		--port 8080:80@loadbalancer \
		--volume $(pwd)/:/$${CLUSTER_NAME}@all \
		--wait
↪this_cluster.auth:
	rmdir $${KUBECONFIG} 2>/dev/null || rm -f $${KUBECONFIG}
	k3d kubeconfig merge $${CLUSTER_NAME} --output $${KUBECONFIG}
↪this_cluster.wait: k8s.wait_for_namespace/all

# END: Cluster-ops
####################################################################################
# BEGIN: Fission Infra/Apps :: 
#   Infra uses `kubectl` container, but apps require the `fission` container for CLI
#   - https://fission.io/docs/installation/
#   - https://fission.io/docs/reference/fission-cli/fission_token_create/
# FIXME: 
# ↪fission_infra.auth: $(eval $(call FISSION_AUTH_TOKEN))
# define FISSION_AUTH_TOKEN
# FISSION_AUTH_TOKEN=`\
# 		kubectl get secrets -n $${FISSION_NAMESPACE} -o json \
# 		| jq -r '.items[]|select(.metadata.name|startswith("fission-router")).data.token' \
# 		| base64 -d`
# endef
export FISSION_NAMESPACE?=fission
export FISSION_VERSION?=v1.20.1
export FUNCTION_NAMESPACE=fission
fission.show: ▰/base/fission.show
↪fission.show:
	kubens fission 
	kubectl get po
	kubectl get svc 
	kubens -
fission_infra.setup: ▰/base/fission_infra.setup this_cluster.wait project.show 
# fission_infra.teardown: ▰/base/fission_infra.teardown
# fission_infra.test: ▰/fission/fission_infra.test
fission_infra.test: ▰/fission/fission_infra.test
↪fission_infra.setup: k8s.namespace.create/$${FISSION_NAMESPACE}
	kubectl create -k "github.com/fission/fission/crds/v1?ref=v1.20.1" || true
	kubectl config set-context --current --namespace=$$FISSION_NAMESPACE
	kubectl apply -f https://github.com/fission/fission/releases/download/v1.20.1/fission-all-v1.20.1-minikube.yaml
	kubectl config set-context --current --namespace=default #to change context to default namespace after installation
	make k8s.wait_for_namespace/fission 
	make k8s.wait_for_namespace/default
# ↪fission_infra.teardown: 
# 	helm uninstall --namespace=$${FISSION_NAMESPACE} fission
↪fission_infra.test: #fission_infra.auth
	set -x \
	&& fission version \
	&& fission check
fission_app.setup: fission_infra.test ▰/fission/fission_app.deploy compose.wait/5 fission_app.test
fission_app.test: ▰/fission/fission_app.test
↪fission_app.deploy: k8s.kubens/default
	( fission env list | grep fission/python-env ) \
		|| fission env create --name python --image fission/python-env
↪fission_app.test: ↪this_cluster.wait k8s.kubens/default
	@#
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
knative: knative_infra.teardown knative_infra.setup knative_app.setup
knative_infra.setup: ▰/base/knative_infra.setup
knative_infra.test: ▰/kn/knative_infra.test
knative_infra.teardown: ▰/base/knative_infra.teardown
↪knative_infra.setup: #↪knative_infra.operator ↪knative_infra.serving
	kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.14.0/serving-crds.yaml
	kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.14.0/serving-core.yaml
	kubectl apply -f https://github.com/knative/eventing/releases/download/knative-v1.14.1/eventing-crds.yaml
	kubectl apply -f https://github.com/knative/eventing/releases/download/knative-v1.14.1/eventing-core.yaml
	kubectl get pods -n knative-eventing
# ↪knative_infra.operator:
# 	#kubectl create -f https://github.com/knative/operator/releases/download/knative-v1.5.1/operator-post-install.yaml || true
# 	#kubectl apply -f https://github.com/knative/operator/releases/download/knative-v1.14.0/operator.yaml || true
# ↪knative_infra.serving:
# 	kubectl apply --validate=false -f https://github.com/knative/serving/releases/download/v0.25.0/serving-crds.yaml
# 	kubectl apply --validate=false -f https://github.com/knative/serving/releases/download/v0.25.0/serving-core.yaml
# ↪knative_infra.auth:
# 	echo knative_infra.auth placeholder
↪knative_infra.test: k8s.kubens/knative-serving
	func version
	kn version
	kubectl get pods
	cd src/knf/; tree
↪knative_infra.teardown: 
	make k8s.namespace.list \
	| grep $${KNATIVE_NAMESPACE_PREFIX} \
	| xargs -n1 -I% bash -x -c "namespace=% make k8s.namespace.purge"

knative_app.test: ▰/kn/knative_app.test
knative_app.setup: ▰/kn/knative_app.setup
↪knative_app.setup:
	echo app-placeholder
↪knative_app.test:
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
export ARGO_EVENTS_URL:=https://raw.githubusercontent.com/argoproj/argo-events

# argo: argo_infra argo_app

# argo_infra: argo_infra.teardown argo_infra.setup compose.wait/60 argo_infra.test

argo_infra.setup: ▰/base/argo_infra.workflows ▰/base/argo_infra.events 
↪argo_infra.workflows: k8s.kubens.create/argo
	kubectl apply -f https://github.com/argoproj/argo-workflows/releases/download/v3.5.4/install.yaml

# FIXME: pin versions
↪argo_infra.events: k8s.kubens.create/argo-events
	kubectl apply -f ${ARGO_EVENTS_URL}/stable/manifests/install.yaml
	kubectl apply -n argo-events -f ${ARGO_EVENTS_URL}/6a44acd1ac57a52/examples/eventbus/native.yaml
	kubectl apply -n argo-events -f ${ARGO_EVENTS_URL}/6a44acd1ac57a52/examples/event-sources/webhook.yaml
	kubectl apply -n argo-events -f ${ARGO_EVENTS_URL}/6a44acd1ac57a52/examples/rbac/sensor-rbac.yaml
	kubectl apply -n argo-events -f ${ARGO_EVENTS_URL}/6a44acd1ac57a52/examples/rbac/workflow-rbac.yaml
	# kubectl apply -n argo-events -f ${ARGO_EVENTS_URL}/6a44acd1ac57a52/examples/sensors/webhook.yaml
	kubectl apply -n argo-events -f src/argo/webhook.sensor.yaml
argo_infra.teardown: ▰/base/argo_infra_teardown
↪argo_infra_teardown: 
	# namespace_prefix=$${ARGO_NAMESPACE_PREFIX} make k8s.purge.namespaces_by_prefix

argo_infra.expose: ▰/kubefwd/argo_infra.expose
↪argo_infra.expose: k8s.kubens/argo-events
	kubefwd svc -v -f metadata.name=webhook-eventsource-svc
argo_infra.test: ▰/base/argo_infra.test_harness ▰/base/argo_infra.test_webhook
↪argo_infra.test_harness: k8s.kubens/argo-events
	export pod_image="alpine/k8s:1.30.0" pod_name=test-harness \
	&& kubectl delete pod $${pod_name} --now --wait || true \
	&& namespace=`kubens -c` make k8s.test_pod.in_namespace \
	&& set -x \
	&& kubectl wait --for=condition=Ready pod/$${pod_name} --timeout=999s
↪argo_infra.test_webhook: k8s.kubens/argo-events
	export tmpf=`mktemp` && trap "rm -f $${tmpf}" EXIT \
	&& set -x \
	&& kubectl get svc \
		webhook-eventsource-svc \
		-o json \
		| jq .spec > $${tmpf} \
	&& cat $$tmpf \
	&& export ip=`cat $${tmpf}|jq -r .clusterIP` \
	&& export port=`cat $${tmpf}|jq -r .ports[0].port`  \
	&& kubectl exec -i \
		test-harness -- /bin/bash -c "curl -s \
			-d '{\"message\":\"this is my first webhook\"}' \
			-H \"Content-Type: application/json\" \
			-X POST http://$${ip}:$${port}/example"

argo_app: ▰/argo/argo_app.setup
↪argo_app.setup: k8s.kubens/argo-events

argo_app.test: ▰/argo/argo_app.test
↪argo_app.test: k8s.kubens/argo-events
	kubectl get po
	kubectl get svc
	argo version
	kubectl -n argo-events get workflows | grep "webhook"
	argo list | grep webhook
	argo get @latest