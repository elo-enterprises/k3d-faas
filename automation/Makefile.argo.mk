# https://argoproj.github.io/argo-events/quick_start/

argo.setup: argo.infra.setup argo.app.setup

argo.shell: k8s.shell/argo/test-harness
argo.stat: argo.wait ▰/k8s/self.argo.stat
argo.test: cluster.wait argo.infra.test argo.app.test
argo.wait: ▰/k8s/k8s.namespace.wait/argo ▰/k8s/k8s.namespace.wait/argo-events

argo.benchmark/%:
	cat=argo target=argo.test_webhook make benchmark/${*}

## Argo Infrastructure
argo.infra.setup: \
	▰/k8s/self.argo.workflows \
	▰/k8s/self.argo.events 

argo.infra.test: \
	▰/k8s/self.argo.test_harness \
	▰/k8s/self.argo.test_webhook
argo.test_webhook: ▰/k8s/self.argo.test_webhook
argo.infra.fwd: kubefwd.namespace/argo-events
	env

## Argo App
argo.app.setup: ▰/argo/self.argo.app.setup

argo.app.test: ▰/argo/self.argo.app.test
self.argo.workflows: k8s.kubens.create/argo
	kubectl apply -f https://github.com/argoproj/argo-workflows/releases/download/${ARGO_WF_VERSION}/install.yaml
self.argo.events: k8s.kubens.create/argo-events
	kubectl apply -f src/argo/events.install.yaml
	kubectl apply -n argo-events -f src/argo/eventbus.native.yaml
	kubectl apply -n argo-events -f src/argo/event-sources.webhook.yaml
	kubectl apply -n argo-events -f src/argo/sensor-rbac.yaml
	kubectl apply -n argo-events -f src/argo/workflow-rbac.yaml
	kubectl apply -n argo-events -f src/argo/webhook.sensor.yaml
self.argo.test_harness: k8s.test_harness/argo-events/test-harness

self.argo.svc_ip: \
	k8s.get/argo-events/svc/webhook-eventsource-svc/.spec.clusterIP
self.argo.svc_port: \
	k8s.get/argo-events/svc/webhook-eventsource-svc/.spec.ports[0].port
self.argo.test_webhook: k8s.kubens/argo-events
	export port=`make self.argo.svc_port` \
	&&  printf "\
		curl -s -d '{\"message\":\"this is my first webhook\"}' \
			-H 'Content-Type: application/json' \
			-X POST http://`make self.argo.svc_ip`:$${port}/example" \
	| make k8s.shell/argo-events/test-harness/pipe
self.argo.app.setup: k8s.kubens/argo-events
self.argo.app.test: k8s.kubens/argo-events
	argo version
	kubectl -n argo-events get workflows | grep "webhook"
	argo list | grep webhook
	argo get @latest

self.argo.stat:
	set -x && kubens|grep argo 
	make io.print.divider 
	make k8s.get/argo/pods|jq .
	make io.print.divider 
	make k8s.get/argo-events/pods|jq .
