#
prometheus: prometheus.setup 

prometheus.wait: k8s.namespace.wait/prometheus

prometheus.setup: \
	▰/k8s/self.prometheus.setup \
	prometheus.fwd 

prometheus.fwd:
	mapping='--mapping 80:8009' make kubefwd.namespace/prometheus/prometheus-server

prometheus.test: k8s.namespace.wait/prometheus
	make prometheus.store_metric key=test cat=test val=3.14
	curl http://prometheus-server:8009

prometheus.store_metric:
	echo "\
		echo \"$${key} $${val}\" \
		| curl -s --data-binary @- http://prometheus-prometheus-pushgateway:9091/metrics/job/$${cat} \
	" | make k8s.shell/prometheus/test-harness/pipe

benchmark/%: 
	for i in {1..${*}}; \
	do \
		make prometheus.store_metric \
			cat=$${cat} \
			key=response_time \
			val=$$(make io.time.target/$${target}); \
	done

##### Private targets (these run inside containers) ###########################
self.prometheus.setup: k8s.kubens.create/prometheus 
	make helm.repo.add/prometheus-community \
		url=https://prometheus-community.github.io/helm-charts
	make helm.chart.install/prometheus \
		chart=prometheus-community/prometheus 
	make k8s.test_harness/prometheus 
	make prometheus.wait 
