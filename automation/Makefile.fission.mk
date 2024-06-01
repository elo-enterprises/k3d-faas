
fission.benchmark/%:
	cat=fission target=fission.app.test make benchmark/${*}
##### User-facing targets ##########################################################
fission.setup: fission.infra.setup fission.wait fission.app.setup fission.wait
fission.show: ▰/k8s/self.fission.app.show
fission.wait: k8s.namespace.wait/fission
fission.test: fission.infra.test fission.app.test
fission.infra.setup: ▰/k8s/self.fission.infra.setup cluster.stat
# fission.infra.teardown: ▰/k8s/self.fission.infra.teardown
fission.infra.test: ▰/fission/self.fission.infra.test
fission.app.setup: fission.infra.test ▰/fission/self.fission.app.deploy
fission.app.test: ▰/fission/self.fission.app.test


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
# self.fission.infra.teardown: k8s.namespace.purge/$${FISSION_NAMESPACE}
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
