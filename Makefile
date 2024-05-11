##
# Project automation.
#
# Typical usage: `make clean init test`
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
$(eval $(call compose.import, ▰, ↪, FALSE, ${PROJECT_ROOT}/k8s-tools.yml))
$(eval $(call compose.import, ▰, ↪, TRUE, ${PROJECT_ROOT}/docker-compose.yml))

bash: 
	env bash -l
shell: k8s-tools/base/shell
k9: k8s-tools/k9s
panic: docker.panic


show: ▰/kubectl/show
↪show:
	@#
	echo CLUSTER_NAME=$${CLUSTER_NAME}
	echo KUBECONFIG=$${KUBECONFIG}
	kubectl cluster-info
	kubectl get nodes
	kubectl get namespace

clean: this_cluster.clean compose.clean
init: compose.build this_cluster.init this_cluster.auth delay/5 show fission.init knative.init
test: fission.test fission_app.test knative.test

this_cluster.init: ▰/k3d/this_cluster.init
this_cluster.auth:  ▰/k3d/this_cluster.auth
this_cluster.clean: ▰/k3d/this_cluster.clean
↪this_cluster.auth:
	rmdir $${KUBECONFIG} 2>/dev/null || rm -f $${KUBECONFIG}
	k3d kubeconfig merge $${CLUSTER_NAME} --output $${KUBECONFIG}
↪this_cluster.clean:
	k3d cluster delete $${CLUSTER_NAME}
↪this_cluster.init:
	(k3d cluster list | grep $${CLUSTER_NAME} ) \
	|| k3d cluster create \
		--config $${CLUSTER_CONFIG} \
		--api-port 6551 --servers 1 \
		--agents $${CLUSTER_AGENT_COUNT} \
		--port 8080:80@loadbalancer \
		--volume $(pwd)/:/$${CLUSTER_NAME}@all \
		--wait



# https://knative.run/article/How_to_deploy_a_Knative_function_on_Kubernetes.html
#####################################################################
knative.init: ▰/kubectl/knative_infra.init ▰/kn/knative_app.init
knative.test: ▰/kn/knative_infra.test ▰/kn/knative_app.test
↪knative_infra.init:
	kubectl create -f https://github.com/knative/operator/releases/download/knative-v1.5.1/operator-post-install.yaml || true
	kubectl apply -f https://github.com/knative/operator/releases/download/knative-v1.14.0/operator.yaml || true
	kubectl apply -f https://github.com/knative/serving/releases/download/v0.25.0/serving-crds.yaml
	kubectl apply -f https://github.com/knative/serving/releases/download/v0.25.0/serving-core.yaml
↪knative_infra.auth: 
	echo auth-placeholder
↪knative_infra.test:
	func version
	kn version
	kubectl get pods --namespace knative-serving
	cd src/knf/
↪knative_app.init: 
	echo app-placeholder
↪knative_app.test:
	echo test-placeholder

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
fission.init: ▰/kubectl/fission.create delay/70 show fission_app.init
fission_app.init: fission.test 
fission_app.init: ▰/fission/provision/fission delay/35 fission_app.test
create/fission: ▰/kubectl/fission.delete ▰/kubectl/fission.create
↪fission.delete:
	kubectl delete namespace --cascade=background $${FISSION_NAMESPACE} 2>/dev/null || true
↪fission.create:
	kubectl create -k "github.com/fission/fission/crds/v1?ref=v1.20.1" || true
	kubectl create namespace $${FISSION_NAMESPACE}
	kubectl config set-context --current --namespace=$${FISSION_NAMESPACE}
	kubectl apply -f https://github.com/fission/fission/releases/download/v1.20.1/fission-all-v1.20.1-minikube.yaml
	kubectl config set-context --current --namespace=default
↪auth/fission: $(eval $(call FISSION_AUTH_TOKEN))
↪provision/fission: ↪auth/fission
	( fission env list | grep fission/python-env ) \
		|| fission env create --name python --image fission/python-env
fission.test: ▰/fission/fission.test 
fission_app.test: ▰/fission/fission_app.test
↪fission.test: ↪auth/fission
	fission version && echo "----------------------"
	fission check && echo "----------------------"
↪fission_app.test: ↪auth/fission
	@#
	(fission function list | grep fission-app) \
		|| fission function create --name fission-app --env python --code src/fission/app.py \
	&& fission function test --timeout=0 --name fission-app

