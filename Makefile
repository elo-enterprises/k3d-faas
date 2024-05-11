##
# Project automation.
#
# Typical usage: `make clean bootstrap build test`
# 	`clean`: tears down the k3d cluster and all apps
# 	`bootstrap`: bootstraps the k3d cluster and cluster-auth
# 	`build`: deploy all apps to cluster
# 	`clean`: tears down the cluster an all apps
#
##
SHELL := bash
MAKEFLAGS += -s --warn-undefined-variables
.SHELLFLAGS := -euo pipefail -c
THIS_MAKEFILE := $(abspath $(firstword $(MAKEFILE_LIST)))
THIS_MAKEFILE := `python -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' ${THIS_MAKEFILE}`

SRC_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null || pwd)
PROJECT_ROOT := $(shell dirname ${THIS_MAKEFILE})
export SRC_ROOT PROJECT_ROOT

export CLUSTER_NAME?=faas
export CLUSTER_AGENT_COUNT?=12
export CLUSTER_CONFIG?=faas.cluster.k3d.yaml
export KUBECONFIG:=./${CLUSTER_NAME}.profile.yaml

#####################################################################

# Creates dynamic targets from compose services.
# See the docs at FIXME
include Makefile.compose.mk
$(eval $(call compose.import, ▰, ↪, TRUE, ${PROJECT_ROOT}/k8s-tools.yml))
$(eval $(call compose.import, ▰, ↪, TRUE, ${PROJECT_ROOT}/docker-compose.yml))

bash: compose.bash
shell: k8s-tools/base/shell
k9s k9: k8s-tools/k9s
panic: docker.panic


project.show: ▰/kubectl/show
↪show:
	@#
	echo CLUSTER_NAME=$${CLUSTER_NAME}
	echo KUBECONFIG=$${KUBECONFIG}
	kubectl cluster-info
	kubectl get nodes
	kubectl get namespace

clean: this_cluster.clean compose.clean
bootstrap: docker.init compose.init this_cluster.bootstrap project.show

deploy: deploy.infra deploy.apps
deploy.infra: fission_infra.setup knative_infra.setup
deploy.apps: fission_app.setup knative_app.setup

test: fission_infra.test fission_app.test knative_infra.test knative_app.test

this_cluster.bootstrap: ▰/k3d/this_cluster.setup ▰/k3d/this_cluster.auth
this_cluster.clean: ▰/k3d/this_cluster.clean
↪this_cluster.clean:
	k3d cluster delete $${CLUSTER_NAME}
↪this_cluster.setup:
	(k3d cluster list | grep $${CLUSTER_NAME} ) \
	|| k3d cluster create \
		--config $${CLUSTER_CONFIG} \
		--api-port 6551 --servers 1 \
		--agents $${CLUSTER_AGENT_COUNT} \
		--port 8080:80@loadbalancer \
		--volume $(pwd)/:/$${CLUSTER_NAME}@all \
		--wait
↪this_cluster.auth:
	rmdir $${KUBECONFIG} 2>/dev/null || rm -f $${KUBECONFIG}
	k3d kubeconfig merge $${CLUSTER_NAME} --output $${KUBECONFIG}



# https://fission.io/docs/installation/
# https://fission.io/docs/reference/fission-cli/fission_token_create/
#####################################################################
export FISSION_NAMESPACE?=fission
define FISSION_AUTH_TOKEN
FISSION_AUTH_TOKEN=`\
		kubectl get secrets -n $${FISSION_NAMESPACE} -o json \
		| jq -r '.items[]|select(.metadata.name|startswith("fission-router")).data.token' \
		| base64 -d`
endef
fission_infra.setup: ▰/kubectl/fission_infra.setup compose.wait/30 project.show
↪fission_infra.setup:
	kubectl create -k "github.com/fission/fission/crds/v1?ref=v1.20.1" || true
	kubectl create namespace $${FISSION_NAMESPACE}
	kubectl config set-context --current --namespace=$${FISSION_NAMESPACE}
	kubectl apply -f https://github.com/fission/fission/releases/download/v1.20.1/fission-all-v1.20.1-minikube.yaml
	kubectl config set-context --current --namespace=default
# ↪fission_infra.auth: $(eval $(call FISSION_AUTH_TOKEN))
fission_infra.teardown:
	kubectl delete namespace --cascade=background $${FISSION_NAMESPACE} 2>/dev/null || true
fission_infra.test: ▰/fission/fission_infra.test
↪fission_infra.test: #fission_infra.auth
	fission version && echo "----------------------"
	fission check && echo "----------------------"

fission.test: ▰/fission/fission.test

fission_app.setup: fission_infra.test
fission_app.setup: ▰/fission/fission_app.deploy
fission_app.setup: compose.wait/35 fission_app.test
fission_app.test: ▰/fission/fission_app.test
↪fission_app.deploy:
	( fission env list | grep fission/python-env ) \
		|| fission env create --name python --image fission/python-env
↪fission_app.test:
	@#
	(fission function list | grep fission-app) \
		|| fission function create --name fission-app --env python --code src/fission/app.py \
	&& fission function test --timeout=0 --name fission-app

# https://knative.run/article/How_to_deploy_a_Knative_function_on_Kubernetes.html
#####################################################################
knative_infra.setup: ▰/kubectl/knative_infra.setup
knative_infra.test: ▰/kn/knative_infra.test
↪knative_infra.setup:
	kubectl create -f https://github.com/knative/operator/releases/download/knative-v1.5.1/operator-post-install.yaml || true
	kubectl apply -f https://github.com/knative/operator/releases/download/knative-v1.14.0/operator.yaml || true
	make ↪knative_infra.serving
↪knative_infra.serving:
	kubectl apply -f https://github.com/knative/serving/releases/download/v0.25.0/serving-crds.yaml
	kubectl apply -f https://github.com/knative/serving/releases/download/v0.25.0/serving-core.yaml
↪knative_infra.auth:
	echo knative_infra.auth placeholder
↪knative_infra.test:
	func version
	kn version
	kubectl get pods --namespace knative-serving
	cd src/knf/; tree
knative_app.test: ▰/kn/knative_app.test
knative_app.setup: ▰/kn/knative_app.setup
↪knative_app.setup:
	echo app-placeholder
↪knative_app.test:
	echo test-placeholder
