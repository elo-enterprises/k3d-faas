cluster.shell: k8s.shell/default/test-harness
cluster.clean: ▰/k3d/k3d.cluster.delete/$${CLUSTER_NAME}
cluster.test: ▰/k3d/self.cluster.test
cluster.wait: ▰/k8s/k8s.pods.wait_until_ready

cluster.stat: ▰/k8s/k8s.stat
cluster.bootstrap: \
	▰/k3d/self.registries.setup \
	▰/k3d/self.cluster.setup \
	▰/k3d/self.cluster.auth \
	cluster.wait \
	cluster.test
cluster.stat: ▰/k8s/k8s.stat

##### Private targets (these run inside containers) ###########################

self.cluster.test: k8s.namespace.wait/default io.time.wait/3 k8s.test_harness/default
	kubectl popeye || true

self.registries.setup: self.registries.dockerio #self.registries.quayio 

self.registries.dockerio:
	k3d registry ls | grep docker-io \
	|| k3d registry create \
		docker-io -p 5000 \
		--proxy-remote-url https://registry-1.docker.io \
		-v ~/.local/share/docker-io-registry:/var/lib/registry

self.cluster.setup:
	@# Setup for the K3d cluster
	@#
	@k3d --version
	@k3d cluster list | grep $${CLUSTER_NAME} \
	|| (set -x && k3d cluster create \
		--config $${CLUSTER_CONFIG} \
		--registry-use k3d-docker-io:5000 \
		--registry-config faas.registries.k3d.yml \
		--volume $$(pwd)/:/$${CLUSTER_NAME}@all \
		--wait)
self.cluster.auth:
	@# Setup authentication for the cluster
	@# NB: The KUBECONFIG here is already project-local;
	@# we ignore whatever is coming from the parent environment
	# rmdir $${KUBECONFIG} 2>/dev/null || rm -f $${KUBECONFIG}
	# set -x && k3d kubeconfig merge $${CLUSTER_NAME} --output $${KUBECONFIG}
