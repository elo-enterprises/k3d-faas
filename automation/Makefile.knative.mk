test.knative: cluster.wait knative.infra.test knative.app.test

knative.infra.setup: ▰/k8s/self.knative.infra.setup
# knative.infra.teardown: ▰/k8s/self.knative.infra.teardown
knative.infra.test: ▰/kn/self.knative.infra.test
knative.app.setup: ▰/kn/self.knative.app.setup
knative.app.test: ▰/kn/self.knative.app.test
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
# self.knative.infra.teardown: k8s.purge_namespaces_by_prefix/knative
self.knative.infra.test: k8s.kubens/knative-serving
	func version
	kn version
	kubectl get pods
	cd src/knf/; tree
self.knative.app.setup:
	echo app-placeholder
self.knative.app.test:
	echo test-placeholder
