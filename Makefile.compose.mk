##
# Makefile.compose.mk
#
# This is designed to be used as an `include` from your project's main Makefile.
#
# DOCS: https://github.com/elo-enterprises/k8s-tools#Makefile.compose.mk
#
# LATEST: https://github.com/elo-enterprises/k8s-tools/tree/master/Makefile.compose.mk
#
# USAGE: (Add this to your project Makefile)
#      include Makefile.compose.mk
#      $(eval $(call compose.import, ▰, ., docker-compose.yml))
#
#      # example for target dispatch:
#      # a target that runs inside the `debian` container
#      demo: ▰/debian/demo
#      .demo:
#      		uname -n -v
#
# USAGE: (Via CLI Interface)
#      # drop into debugging shell for the container
#      make <stem_of_compose_file>/<name_of_compose_service>/shell
#
#      # stream data into container
#      echo echo hello-world | make <stem_of_compose_file>/<name_of_compose_service>/shell/pipe
#
#      # show full interface (see also: https://github.com/elo-enterprises/k8s-tools#makecompose-bridge)
#      make help
#
# APOLOGIES: In advance if you're checking out the implementation.
#      Make-macros are not the most fun stuff to read or write.
#      Pull requests are welcome! =P
########################################################################
## BEGIN: data
export COLOR_GREEN:=\033[92m
export NO_COLOR:=\033[0m
export COLOR_DIM:=\033[2m
export COLOR_RED=\033[91m
export COMPOSE_IGNORE_ORPHANS:=True
export COMPOSE_MK?=0
export COMPOSE_MK_POLL_DELTA?=5

## END: data
########################################################################
## BEGIN: macros

# Macro to yank all the compose-services out of YAML.  
# This drops into python unfortunately and that's a significant dependency.  
# But bash or awk would be a nightmare, and even perl requires packages to be
# installed before it can parse YAML.  To work around this, the COMPOSE_MK 
# env-var is checked, so that inside containers `compose.get_services` always 
# returns nothing.
define compose.get_services
	$(shell if [ "${COMPOSE_MK}" = "0" ]; then cat ${1} | python3 -c 'import yaml, sys; data=yaml.safe_load(sys.stdin.read()); svc=data["services"].keys(); print(" ".join(svc))'; else echo -n ""; fi)
endef

# Macro to create all the targets for a given compose-service
define compose.create_make_targets
$(eval compose_service_name := $1)
$(eval target_namespace := $2)
$(eval dispatch_prefix := $3)
$(eval import_to_root := $(strip $4))
$(eval compose_file := $(strip $5))
$(eval namespaced_service:=${target_namespace}/$(compose_service_name))
$(eval relf:=$(shell basename -s .yml $(compose_file)))

${relf}/$(compose_service_name)/shell:
	@export entrypoint=`docker compose -f $(compose_file) \
		run --entrypoint sh $$(shell echo $$@|awk -F/ '{print $$$$2}') \
		-c "which bash || which sh" \
		2>/dev/null \
		|| printf "$${COLOR_RED}Neither 'bash' nor 'sh' are available!\n(service=${compose_service_name} @ ${compose_file})\n$${NO_COLOR}" > /dev/stderr` \
	&& ( \
		( env|grep entrypoint\= &>/dev/null \
			|| exit 1 ) \
		&& make ${relf}/$(compose_service_name) \
	)

${relf}/$(compose_service_name)/shell/pipe:
	pipe=yes \
		make ${relf}/$(compose_service_name)/shell

${relf}/$(compose_service_name)/pipe:
	cat /dev/stdin | make ⟂/${relf}/$(compose_service_name)

$(eval ifeq ($$(import_to_root), TRUE)
$(compose_service_name): $(target_namespace)/$(compose_service_name)
$(compose_service_name)/pipe: ⟂/${relf}/$(compose_service_name)
$(compose_service_name)/shell: ${relf}/$(compose_service_name)/shell
$(compose_service_name)/shell/pipe: 
	cat /dev/stdin \
	| pipe=yes make ${relf}/$(compose_service_name)/shell
endif)

${target_namespace}/$(compose_service_name):
	@# A namespaced target for each docker-compose service
	make ${relf}/$$(shell echo $$@|awk -F/ '{print $$$$2}')

${target_namespace}/$(compose_service_name)/%:
	@# A subtarget for each docker-compose service.
	@# This allows invocation of *another* make-target
	@# that runs inside the container
	@echo COMPOSE_MK=1 make ${dispatch_prefix}$${*} \
		| make ⟫/${relf}/$(compose_service_name)
endef

# Main macro to import services from an entire compose file
define compose.import
$(eval target_namespace:=$1)
$(eval dispatch_prefix:=$2)
$(eval import_to_root := $(if $(3), $(strip $(3)), FALSE))
$(eval compose_file:=$(strip $4))
$(eval relf:=$(shell basename -s .yml $(strip ${4})))
$(eval __services__:=$(call compose.get_services, ${compose_file}))

⟫/${relf}/%:
	@entrypoint=bash make ⟂/${relf}/$${*}

⟂/${relf}/%:
	@pipe=yes make ${relf}/$${*}

${relf}/__services__:
	@echo $(__services__)
${relf}/__build__:
	docker compose -f $${compose_file} build
${relf}/__stop__:
	docker compose -f $${compose_file} stop -t 1
${relf}/__up__:
	docker compose -f $${compose_file} up
${relf}/__clean__:
	set -x && docker compose -f $${compose_file} --progress quiet down -t 1 --remove-orphans

${relf}/%:
	@$$(eval export svc_name:=$$(shell echo $$@|awk -F/ '{print $$$$2}'))
	@$$(eval export cmd:=$(shell echo $${cmd:-}))
	@$$(eval export pipe:=$(shell if [ -z "$${pipe:-}" ]; then echo ""; else echo "-T"; fi))
	@$$(eval export entrypoint:=$(shell if [ -z "$${entrypoint:-}" ]; then echo ""; else echo "--entrypoint $${entrypoint}"; fi))
	@$$(eval export base:=docker compose -f ${compose_file} run -u`id -u`:`id -g` --rm --quiet-pull --env COMPOSE_MK=1 $${pipe} $${entrypoint} $${svc_name} $${cmd} )
	@$$(eval export dispbase:=$$(shell echo $${base}|sed 's/\(.\{5\}\).*/\1.../'))
	@$$(eval export tmpf2:=$$(shell mktemp))
	@if [ -z "$${pipe}" ]; then \
		eval $${base} ; \
	else \
		cat /dev/stdin > $${tmpf2} \
		&& (printf "\
			$${COLOR_GREEN}→ ${COLOR_DIM}container-dispatch \
			\n  ${NO_COLOR}file: ${COLOR_DIM}${COLOR_GREEN}$$(shell basename $${compose_file})${NO_COLOR} \
			\n  ${NO_COLOR}service: ${COLOR_GREEN}$${svc_name}${NO_COLOR} \
			\n  ${NO_COLOR}cmd: ${COLOR_DIM}`cat $${tmpf2} | sed -e 's/COMPOSE_MK=[01]//'`\n$${NO_COLOR}" )  \
		&& trap "rm -f $${tmpf2}" EXIT \
		&& cat "$${tmpf2}" | eval $${base} \
	; fi
$(foreach \
 	compose_service_name, \
 	$(__services__), \
	$(eval \
		$(call compose.create_make_targets, \
			$${compose_service_name}, \
			${target_namespace}, ${dispatch_prefix}, \
			${import_to_root}, ${compose_file}, )))
endef

## END: macros
########################################################################
## BEGIN: meta targets (api-stable)

help:
	@LC_ALL=C $(MAKE) -pRrq -f $(firstword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/(^|\n)# Files(\n|$$)/,/(^|\n)# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | grep -E -v -e '^[^[:alnum:]]' -e '^$@$$' || true


## END: meta targets
########################################################################
## BEGIN: convenience targets (api-stable)
k9s/%:
	@# Opens k9s UI at the given namespace
	make k9s cmd="-n ${*}"
compose.strip_ansi:
	@# Pipe-friendly helper for stripping ansi
	cat /dev/stdin | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g"'
compose.mktemp:
	export tmpf3=`mktemp` \
	&& trap "rm -f $${tmpf3}" EXIT \
	&& echo $${tmpf3}

compose.wait/%:
	printf "${COLOR_DIM}Waiting for ${*} seconds..${NO_COLOR}\n" > /dev/stderr \
	&& sleep ${*}
compose.indent:
	@#
	cat /dev/stdin | sed 's/^/  /'

compose.init:
	@# Ensure compose is available and build it
	docker compose version >/dev/null \
	&& make compose.build

compose.bash:
	@#
	env bash -l

docker.init:
	@# Check if docker is available, no real setup
	docker --version

docker.panic:
	@# Debugging only!  Running this from automation will 
	@# probably quickly hit rate-limiting at dockerhub,
	@# and obviously this is dangerous for production..
	docker rm -f $$(docker ps -qa | tr '\n' ' ')
	docker network prune -f
	docker volume prune -f
	docker system prune -a -f

# NB: looks empty, but don't edit this, it helps make to understand newline literals
define newline


endef

define k8s.test_pod.template
{
	"apiVersion": "v1",
	"kind":"Pod",
	"metadata":{"name": "$(strip ${1})"},
	"spec":{
		"containers": [
			{ "name": "$(strip ${1})-container",
			  "image": "$(strip ${2})",
			  "command": ["sleep","infinity"] }
		]
	} 
}
endef
k8s.kubens/%: 
	@# Context-manager.  Activates the given namespace.
	@# Note that this modifies state in the kubeconfig,
	@# so it can effect contexts outside of the current
	@# process, therefore this is not thread-safe.
	TERM=xterm kubens ${*} 2>&1 > /dev/stderr

.k8s.kubens/%: 
	@# Alias for the top-level target
	TERM=xterm kubens ${*} 2>&1 > /dev/stderr

k8s.kubens.create/%:
	@# Context-manager.  Activates the given namespace, creating it first if necessary.
	@# (This has side-effects and persists for subprocesses)
	make k8s.namespace.create/${*}
	make k8s.kubens/${*}

k8s.test_pod_in_namespace/%:
	$(eval export namespace:=$(strip $(shell echo ${*}|awk -F/ '{print $$1}'))) \
	$(eval export pod_name:=$(strip $(shell echo ${*}|awk -F/ '{print $$2}'))) \
	$(eval export pod_image:=$(strip $(shell echo ${*}|awk -F/ '{print $$3}'))) \
	export manifest=`printf '$(subst $(newline),\n, $(call k8s.test_pod.template, ${pod_name}, ${pod_image}))\n'` \
	&& printf "$${COLOR_DIM}\n$${manifest}\n$${NO_COLOR}" > /dev/stderr \
	&& printf "$${manifest}" \
	| jq . | (set -x && kubectl apply --namespace $${namespace} -f -)
	make k8s.namespace.wait/$${namespace}
.k8s.test_pod_in_namespace/%: 
	make k8s.test_pod_in_namespace/${*}

k8s.namespace/%:
	@# Context-manager.  Activates the given namespace.
	@# (This has side-effects and persists for subprocesses)
	make k8s.kubens/${*}

k8s.namespace.create/%:
	@# Idempotent version of namespace-create
	kubectl create namespace ${*} \
		--dry-run=client -o yaml \
	| kubectl apply -f - \
	2>&1

k8s.namespace.purge/%:
	@# Wipes everything inside the given namespace
	printf "${COLOR_GREEN}${COLOR_DIM}k8s.namespace.purge /${NO_COLOR}${COLOR_GREEN}${*}${NO_COLOR} Waiting for delete (cascade=foreground) \n" > /dev/stderr \
	&& set +x \
	&& kubectl delete namespace \
		--cascade=foreground ${*} \
		-v=9 2>/dev/null || true
k8s.namespace.list:
	@# Returns all namespaces in a simple array 
	@# WARNING: Must remain suitable for use with `xargs`
	kubectl get namespaces -o json \
	| jq -r '.items[].metadata.name'

k8s.purge_namespaces_by_prefix/%:
	@# Runs a separate purge for every matching namespace
	make k8s.namespace.list \
	| grep ${*} \
	|| (\
		printf "${COLOR_DIM}Nothing to purge: no namespaces matching \`${*}*\`${NO_COLOR}\n" \
		> /dev/stderr )\
	| xargs -n1 -I% bash -x -c "make k8s.namespace.purge/%"

k8s.namespace.wait/%:
	@# Waits for every pod in the given namespace to be ready
	@# NB: If the parameter is "all" then this uses --all-namespaces
	@$(eval export tmpf1:=$$(shell mktemp))
	export scope=`[ "${*}" == "all" ] && echo "--all-namespaces" || echo "-n ${*}"` \
	&& export header="${COLOR_GREEN}${COLOR_DIM}k8s.namespace.wait // ${NO_COLOR}" \
	&& export header="$${header}${COLOR_GREEN}${*}${NO_COLOR}" \
	&& printf "$${header} :: Looking for pending pods.. \n" \
		> /dev/stderr \
	&& until \
		kubectl get pods $${scope} -o json \
		| jq '[.items[].status.containerStatuses[]|select(.state.waiting)]' \
		> $${tmpf1} \
		&& printf "$(strip $(shell cat $${tmpf1} | sed -e 's/\[\]//'))" > /dev/stderr \
		&& cat $${tmpf1} | jq '.[] | halt_error(length)' \
	; do \
		export stamp="${COLOR_DIM}`date`${NO_COLOR}" \
		&& printf "$${stamp} Pods aren't ready yet (sleeping $${COMPOSE_MK_POLL_DELTA})\n" > /dev/stderr \
		&& sleep $${COMPOSE_MK_POLL_DELTA}; \
	done \
	&& printf "$${header} :: Namespace looks ready.${NO_COLOR}\n" > /dev/stderr
.k8s.namespace.wait/%:
	@# (Alias in case this is used as a private-target)
	make k8s.namespace.wait/${*}

k8s.pods.wait_until_ready: 
	@# Waits until all pods in every namespace are ready
	make k8s.namespace.wait/all
.k8s.pods.wait_until_ready: k8s.pods.wait_until_ready

k8s.shell/%:
	@# Usage: k8s.shell/<namespace>/<pod>
	@# This drops into a debugging shell for the named pod,
	@# using `kubectl exec`.  This target is unusual because
	@# it MUST run from the host + also uses containers.  
	@# WARNING: 
	@#   This target assumes that k8s-tools.yml is imported
	@#   to the root namespace, and using the default syntax.  
	$(eval export namespace:=$(shell echo ${*}|awk -F/ '{print $$1}')) \
	$(eval export pod_name:=$(shell echo ${*}|awk -F/ '{print $$2}')) \
	make ▰/base/k8s.test_pod_in_namespace/$${namespace}/$${pod_name}/$${pod_image:-debian}
	printf "${COLOR_GREEN}${COLOR_DIM}k8s.shell // ${NO_COLOR}${COLOR_GREEN}$${namespace}${COLOR_DIM} // ${NO_COLOR}${COLOR_GREEN}$${pod_name}${NO_COLOR} :: \n" > /dev/stderr \
	&& set -x \
	&& cmd="exec -n $${namespace} -it ${pod_name} -- bash" make kubectl 

## END: convenience targets
########################################################################
