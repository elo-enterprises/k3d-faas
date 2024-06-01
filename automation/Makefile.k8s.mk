##
# Makefile.k8s.mk
#
# This is designed to be used as an `include` from your project's main Makefile.
#
# DOCS: https://github.com/elo-enterprises/k8s-tools#Makefile.k8s.mk
#
# LATEST: https://github.com/elo-enterprises/k8s-tools/tree/master/Makefile.k8s.mk
#
# USAGE: (Add this to your project Makefile)
#
#      include Makefile.k8s.mk
#
#      demo: ▰/debian/demo
#      .demo:
#      		uname -n -v
#
# APOLOGIES: In advance if you're checking out the implementation.
#      Make-macros are not the most fun stuff to read or write.
#      Pull requests are welcome! =P
########################################################################

export GREEN?=\033[92m
export NO_ANSI?=\033[0m
export DIM?=\033[2m
export UNDERLINE?=\033[4m
export BOLD?=\033[1m
# export YELLOW...
GLYPH_K8S=${GREEN}⑆${DIM}
SEP:=${NO_ANSI}//

export K8S_POLL_DELTA?=23
export ALPINE_K8S_VERSION?=alpine/k8s:1.30.0

helm.repo.add/%:
	@# Idempotent version 'helm repo add'
	@#
	@# USAGE:
	@#   make helm.repo.add/<repo_name> url=<repo_url>
	@#  
	set -x \
	&& (helm repo list 2>/dev/null | grep ${*}) \
	|| helm repo add ${*} $${url} 

helm.chart.install/%:
	@# Idempotent version of a 'helm install'
	@#
	@# USAGE:
	@#   make helm.chart.install/<name> chart=<chart>
	@#  
	set -x \
	&& ( helm list | grep ${*} ) \
	|| helm install ${*} $${chart}

k3d.panic:
	@# Non-graceful stop for everything that is k3d related. 
	@# 
	@# USAGE:  
	@#   make k3d.panic
	@# 
	(make k3d.ps || echo -n) | xargs -I% bash -x -c "docker stop -t 1 %"

k3d.ps:
	@# Container names for everything that is k3d related
	@# 
	@# USAGE:  
	@#   make k3d.ps
	@# 
	set -x \
	&& (docker ps --format json \
	| jq -r '.Names' \
	| grep ^k3d- \
	|| printf "${YELLOW}No containers found.${NO_ANSI}\n" > /dev/stderr )

k3d.cluster.delete/%:
	@# Idempotent version of k3d cluster delete 
	@#
	@# USAGE:
	@#   k3d.cluster.delete/<cluster_name>
	@#
	@( k3d cluster list | grep ${*} > /dev/null ) \
	&& ( set -x && k3d cluster delete ${*} ) || true

k8s.commander/%:
	@# A split-screen TUI dashboard that opens 'lazydocker' and 'ktop'.
	@# (Requires tmux)
	@#
	@# USAGE:  
	@#   make k3d.commander/<namespace>
	@# 
	tmux new-session \; set-option -g default-command "exec /bin/bash -x" \; split-window -h \; send-keys "make ktop/${*}; tmux kill-session" C-m \; select-pane -t 0 \; send-keys "make lazydocker; tmux kill-session" C-m

k8s.commander: k8s.commander/default
	@# Opens k8s.commander for the "default" namespace

k8s.get/%:
	@# Returns resources under the given namespace, for the given kind.
	@# This can also be used with a 'jq' query to grab deeply nested results.
	@# Pipe Friendly: results are always JSON.  Caller should handle errors.
	@#
	@# Argument for 'kind' must be provided, but may be "all".  
	@# Argument for 'filter' is optional.
	@#
	@# USAGE: 
	@#	 k8s.get/<namespace>/<kind>/<resource_name>/<jq_filter>
	@#
	$(eval export pathcomp:=$(shell echo ${*}| sed -e 's/\// /g'))
	$(eval export namespace:=$(strip $(shell echo ${*} | awk -F/ '{print $$1}')))
	$(eval export kind:=$(strip $(shell echo ${*} | awk -F/ '{print $$2}')))
	$(eval export name:=$(strip $(shell echo ${*} | awk -F/ '{print $$3}')))
	$(eval export filter:=$(strip $(shell echo ${*} | awk -F/ '{print $$4}')))
	export cmd_t="kubectl get $${kind} $${name} -n $${namespace} -o json | jq -r $${filter}" \
	&& printf "${GLYPH_K8S} k8s.get${NO_ANSI_DIM} // $${cmd_t}\n${NO_ANSI}" > /dev/stderr \
	&& eval $${cmd_t}

k8s.kubens/%: 
	@# Context-manager.  Activates the given namespace.
	@# NB: This modifies state in the kubeconfig, so that it can effect contexts 
	@# outside of the current process, therefore this is not thread-safe.
	@#
	@# USAGE:  
	@#   make k8s.kubens/<namespace>
	@#
	TERM=xterm kubens ${*} 2>&1 > /dev/stderr

k8s.kubens.create/%:
	@# Context-manager.  Activates the given namespace, creating it first if necessary.
	@#
	@# NB: This modifies state in the kubeconfig, so that it can effect contexts 
	@# outside of the current process, therefore this is not thread-safe.
	@#
	@# USAGE: 
	@#    k8s.kubens.create/<namespace>
	@#
	make k8s.namespace.create/${*}
	make k8s.kubens/${*}

k8s.namespace/%:
	@# Context-manager.  Activates the given namespace.
	@#
	@# NB: This modifies state in the kubeconfig, so that it can effect contexts 
	@# outside of the current process, therefore this is not thread-safe.
	@#
	@# USAGE:  
	@#	 k8s.namespace/<namespace>
	@#
	make k8s.kubens/${*}

k8s.purge_namespaces_by_prefix/%:
	@# Runs a separate purge for every matching namespace.
	@# NB: This isn't likely to clean everything, see the docs for your dependencies.
	@#
	@# USAGE: 
	@#    k8s.purge_namespaces_by_prefix/<prefix>
	@#
	make k8s.namespace.list \
	| grep ${*} \
	|| (\
		printf "${DIM}Nothing to purge: no namespaces matching \`${*}*\`${NO_ANSI}\n" \
		> /dev/stderr )\
	| xargs -n1 -I% bash -x -c "make k8s.namespace.purge/%"

k8s.namespace.create/%:
	@# Idempotent version of namespace-create
	@#
	@# USAGE: 
	@#    k8s.namespace.create/<namespace>
	@#
	kubectl create namespace ${*} \
		--dry-run=client -o yaml \
	| kubectl apply -f - \
	2>&1

k8s.namespace.purge/%:
	@# Wipes everything inside the given namespace
	@#
	@# USAGE: 
	@#    k8s.namespace.purge/<namespace>
	@#
	printf "${GLYPH_K8S} k8s.namespace.purge /${NO_ANSI}${GREEN}${*}${NO_ANSI} Waiting for delete (cascade=foreground) \n" > /dev/stderr \
	&& set +x \
	&& kubectl delete namespace --cascade=foreground ${*} -v=9 2>/dev/null || true
k8s.namespace.list:
	@# Returns all namespaces in a simple array.
	@# NB: Must remain suitable for use with `xargs`!
	@#
	kubectl get namespaces -o json \
	| jq -r '.items[].metadata.name'

k8s.namespace.wait/%:
	@# Waits for every pod in the given namespace to be ready.
	@# This uses kubectl/jq to loop on pod-status, but assumes that 
	@# the krew-plugin 'sick-pods' is available for formatting the 
	@# user-message.
	@#
	@# NB: If the parameter is "all" then this uses --all-namespaces
	@#
	@# USAGE: 
	@#   k8s.namespace.wait/<namespace>
	@#
	@export scope=`[ "${*}" == "all" ] && echo "--all-namespaces" || echo "-n ${*}"` \
	&& export header="${GLYPH_K8S} k8s.namespace.wait ${SEP} " \
	&& export header="$${header}${GREEN}${*}${NO_ANSI}" \
	&& printf "$${header} ${DIM}:: Looking for pending pods.. ${NO_ANSI}\n" > /dev/stderr \
	&& until \
		kubectl get pods $${scope} -o json \
		| jq '[.items[].status.containerStatuses[]|select(.state.waiting)]' \
		| jq '.[] | halt_error(length)' 2> /dev/null \
	; do \
		kubectl sick-pods $${scope} \
			| sed 's/^[ \t]*//'\
			| sed "s/Failed/$(shell printf "${YELLOW}Failed${NO_ANSI}")/g" \
			| sed "s/Scheduled/$(shell printf "${YELLOW}Scheduled${NO_ANSI}")/g" \
			| sed "s/Pulling/$(shell printf "${GREEN}Pulling${NO_ANSI}")/g" \
			| sed "s/Warning/$(shell printf "${YELLOW}Warning${NO_ANSI}")/g" \
			| sed "s/Pod Conditions:/$(shell printf "☂${DIM_GREEN}${UNDERLINE}Pod Conditions:${NO_ANSI}")/g" \
			| sed "s/Pod Events:/$(shell printf "${UNDERLINE}${DIM_GREEN}Pod Events:${NO_ANSI}")/g" \
			| sed "s/Container Logs:/$(shell printf "${UNDERLINE}${DIM_GREEN}Container Logs:${NO_ANSI}")/g" \
			| sed "s/ContainerCreating/$(shell printf "${GREEN}ContainerCreating${NO_ANSI}")/g" \
			| sed "s/ErrImagePull/$(shell printf "${YELLOW}ErrImagePull${NO_ANSI}")/g" \
			| sed "s/ImagePullBackOff/$(shell printf "${YELLOW}ImagePullBackOff${NO_ANSI}")/g" \
			| tr '☂' '\n' |make io.print.dim > /dev/stderr \
		&& printf "${DIM}`date`${NO_ANSI} ${BOLD}Pods aren't ready yet${NO_ANSI_DIM} (waiting $${K8S_POLL_DELTA}s)${NO_ANSI}\n" > /dev/stderr \
		&& sleep $${K8S_POLL_DELTA}; \
	done \
	&& printf "${DIM}$${header} :: ${NO_ANSI}Namespace looks ready.${NO_ANSI}\n" > /dev/stderr

k8s.pods.wait_until_ready: 
	@# Waits until all pods in every namespace are ready.
	@# (No parameters; kube context should already be configured)
	@#
	make k8s.namespace.wait/all
	
k8s.stat:
	@# Describes status for cluster, cluster auth, and namespaces
	@#
	printf "\n${GLYPH_K8S} k8s.stat ${NO_ANSI}${GREEN}${UNDERLINE}`kubectx`${NO_ANSI} \n"
	printf "${DIM}⑆ k8s.stat.env ${NO_ANSI}${NO_ANSI}\n" > /dev/stderr
	env|grep CLUSTER 
	env|grep KUBE 
	env|grep DOCKER
	printf "${DIM}⑆ k8s.stat.cluster_info ${NO_ANSI}${NO_ANSI}\n" > /dev/stderr
	kubectl version | make io.print.ident 
	kubectl cluster-info | grep -v cluster-info | awk NF | make io.print.ident
	printf "${DIM}⑆ k8s.stat.node_info (${NO_ANSI}${GREEN}`kubectl get nodes -oname|wc -l`${NO_ANSI_DIM} total)\n" > /dev/stderr
	printf "${DIM}`kubectl get nodes | make io.print.ident`${NO_ANSI}\n"
	printf "${DIM}⑆ k8s.stat.auth_info ${NO_ANSI}${NO_ANSI}\n" > /dev/stderr
	printf "${DIM}`kubectl auth whoami -ojson | make io.print.ident`${NO_ANSI}\n"
	printf "${DIM}⑆ k8s.stat.namespace_info ${NO_ANSI}${NO_ANSI}\n" > /dev/stderr
	printf "`kubens | make io.print.ident`\n"

k8s.test_harness/%:
	@# Starts a test-pod in the given namespace, then blocks until it's ready.
	@#
	@# USAGE: 
	@#	`k8s.test_harness/<namespace>/<pod_name>` or 
	@#	`k8s.test_harness/<namespace>/<pod_name>/<image>` 
	@#
	$(eval export pathcomp:=$(shell echo ${*}| sed -e 's/\// /g'))
	$(eval export namespace:=$(strip $(shell echo ${*} | awk -F/ '{print $$1}'))) \
	$(eval export pod_name:=$(strip $(shell echo ${*} | awk -F/ '{print $$2}'))) \
	$(eval export rest:=$(strip \
		$(shell echo $(wordlist 3,99,$${pathcomp}) | sed -e 's/ /\//g')))

	@export pod_name=$${pod_name:-test-harness} \
	&& export pod_image=$${rest:-$${ALPINE_K8S_VERSION}} \
	&& export header="${GLYPH_K8S} k8s.test_harness // ${NO_ANSI}" \
	&& printf "$${header}${GREEN}$${namespace}${NO_ANSI}\n" > /dev/stderr \
	&& export data="{ \
		\"apiVersion\": \"v1\", \"kind\":\"Pod\", \
		\"metadata\":{\"name\": \"$${pod_name}\"}, \
		\"spec\":{ \
			\"containers\": [ {\
				\"name\": \"$${pod_name}-container\", \
				\"tty\": true, \"stdin\": true,\
				\"image\": \"$${pod_image}\", \
				\"command\": [\"sleep\", \"infinity\"] } ] } \
		}"\
	&& export manifest=`printf "$${data}" |jq .` \
	&& printf "$${DIM}$${manifest}\n$${NO_ANSI}" > /dev/stderr \
	&& printf "$${manifest}" \
		| jq . \
		| (set -x && kubectl apply --namespace $${namespace} -f -)
	make k8s.namespace.wait/$${namespace}

k8s.shell/%:
	@# This drops into a debugging shell for the named pod using `kubectl exec`,
	@# plus a streaming version of the same which allows for working with pipes.
	@#
	@# NB: This target may run from the docker host or the k8s.  In the former case, 
	@# we assume that k8s-tools.yml is present with that filename and `compose.import` 
	@# was used as usual.
	@#
	@# USAGE: Interactive shell in pod:
	@#   make k8s.shell/<namespace>/<pod_name>
	@#
	@# USAGE: Stream commands into a pod:
	@#   echo uname -a | make k8s.shell/<namespace>/<pod_name>/pipe
	@#
	$(eval export namespace:=$(shell echo ${*}|awk -F/ '{print $$1}'))
	$(eval export pod_name:=$(shell echo ${*}|awk -F/ '{print $$2}'))
	$(eval export rest:=$(shell echo ${*}|awk -F/ '{print $$3}'))
	$(eval export cmd:=$(shell [ "${rest}" == "pipe" ] \
			&& echo "exec -n ${namespace} -i ${pod_name} -- bash" \
			|| echo "exec -n ${namespace} -it ${pod_name} -- bash" ))
	$(eval export k8s_shell_tmpf:=$$(shell mktemp))
	case "$${rest}" in \
		pipe) \
			cat /dev/stdin > $${k8s_shell_tmpf}; \
			([ "$${COMPOSE_MK:-0}" = "0" ] \
				&& (cat $${k8s_shell_tmpf} | pipe=yes cmd="$${cmd}" entrypoint=kubectl make k8s-tools/k8s) \
				|| ( printf "${GLYPH_K8S} k8s.shell${NO_ANSI_DIM} // ${NO_ANSI}${GREEN}$${namespace}${NO_ANSI_DIM} // ${NO_ANSI}${GREEN}${UNDERLINE}$${pod_name}${NO_ANSI_DIM} \n${CYAN}[${NO_ANSI}${BOLD}kubectl${NO_ANSI_DIM}${CYAN}]${NO_ANSI} ${NO_ANSI_DIM}${ITAL}${cmd}${NO_ANSI}\n${CYAN_FLOW_LEFT} ${DIM_ITAL}`cat $${k8s_shell_tmpf}|make io.fmt.strip`${NO_ANSI}\n" > /dev/stderr && cat $${k8s_shell_tmpf} | kubectl $${cmd}) ); ;; \
		*) \
			[ "$${COMPOSE_MK:-0}" = "0" ] \
			&& (cmd="$${cmd}" entrypoint=kubectl make k8s-tools/k8s) \
			|| kubectl $${cmd}; ;; \
        esac

kubefwd.panic:
	@# Non-graceful stop for everything that is kubefwd related.
	@# 
	@# NB: this can clutter up your /etc/hosts file if kubefwd doesn't clean up things.
	@# 
	@# USAGE:  
	@#   make kubefwd.panic
	(make kubefwd.ps || echo -n) | xargs -I% bash -x -c "docker stop -t 1 %"

kubefwd.ps:
	@# Container names for everything that is kubefwd related
	@# 
	@# USAGE:  
	@#   make kubefwd.ps
	@# 
	set -x \
	&& (docker ps --format json \
	| jq -r '.Names' \
	| grep kubefwd \
	|| printf "${YELLOW}No containers found.${NO_ANSI}\n" > /dev/stderr )

k8s.namespace.fwd/%:
	@# Alias for 'kubefwd.namespace'
	@#
	make kubefwd.namespace/${*}

kubefwd.namespace/%:
	@# Runs kubefwd for the given namespace, finding and forwarding ports/DNS for the given 
	@# service, or for all services. This is idempotent, and implicitly stops port-forwarding 
	@# if it is running, then restarts it. 
	@#
	@# NB: This target should only run from the docker host (not from the kubefwd container),  
	@# and it assumes k8s-tools.yml is present with that filename. Simple port-mapping and 
	@# filtering by name is supported; other usage with selectors/labels/reservations/etc 
	@# should just invoke kubefwd directly.
	@#
	@# USAGE: 
	@#   make kubefwd/<namespace>
	@#	 make kubefwd/<namespace> mapping="-m 8080:80"
	@#   make kubefwd/<namespace>/<svc_name>
	@#   make kubefwd/<namespace>/<svc_name>  mapping="-m 8080:80"
	@#
	$(eval export pathcomp:=$(shell echo ${*}| sed -e 's/\// /g'))
	$(eval export namespace:=$(strip $(shell echo ${*} | awk -F/ '{print $$1}')))
	$(eval export svc_name:=$(strip $(shell echo ${*} | awk -F/ '{print $$2}')))
	mapping=$${mapping:-} \
	&& header="${GLYPH_K8S} kubefwd.namespace ${SEP} ${DIM_GREEN}$${namespace}" \
	&& case "$${svc_name}" in \
		"") \
			filter=$${filter:-}; ;; \
		*) \
			filter="-f metadata.name=$${svc_name}"; \
			header="$${header} ${SEP} ${BOLD_GREEN}$${svc_name}"; ;; \
	esac \
	&& cname=kubefwd.`basename ${PWD}`.$${namespace}.$${svc_name:-all} \
	&& (timeout=30 name=$${cname} make docker.stop || true) \
	&& fwd_cmd="kubefwd svc -n $${namespace} $${filter} $${mapping} -v" \
	&& fwd_cmd_wrapped="docker compose -f k8s-tools.yml run --name $${cname} --rm -d $${fwd_cmd}" \
	&& printf "$${header}${NO_ANSI}\n" > /dev/stderr \
	&& echo {} \
		| make io.json.builder key=fwd.container val="$${cname}" \
		| make io.json.builder key=target.namespace val="$${namespace}" \
		| make io.json.builder key=target.svc val="$${svc_name}" \
		| make io.json.builder key=fwd.cmd val="$${fwd_cmd}" | make io.print.dim.indent > /dev/stderr \
	&& printf "$${fwd_cmd_wrapped}\n"|make io.print.dim > /dev/stderr \
	&& cid=`$${fwd_cmd_wrapped}` && cid=$${cid:0:8} \
	&& cmd="docker logs -f $${cname}" timeout=3 make io.time.wait_for_command 

ktop: ktop/all
	@# Launches ktop tool.  
	@# (This assumes 'ktop' is mentioned in 'KREW_PLUGINS')

ktop/%:
	@# Launches ktop tool for the given namespace.
	@# This works from inside a container or from the host.
	@#
	@# NB: It's the default, but this does assume 'ktop' is mentioned in 'KREW_PLUGINS'
	@#
	@# USAGE:
	@#   ktop/<namespace>
	@#
	@scope=`[ "${*}" == "all" ] && echo "--all-namespaces" || echo "-n ${*}"` \
	&& [ "$${COMPOSE_MK:-0}" = "0" ] \
		&& cmd="ktop $${scope}" entrypoint=kubectl make k8s \
		|| kubectl ktop $${scope}


k9s/%:
	@# Starts the k9s pod-browser TUI, opened by default to the given namespace.
	@# 
	@# NB: This assumes the `compose.import` macro has already imported k8s-tools services
	@# 
	@# USAGE:  
	@#   make k9s/<namespace>
	@#
	make k9s cmd="-n ${*}"

k9: k9s
	@# Starts the k9s pod-browser TUI, using whatever namespace is currently activated.
	@# 
	@# NB: This assumes the `compose.import` macro has already imported k8s-tools services
	@#
	@# USAGE:  
	@#   make k9

