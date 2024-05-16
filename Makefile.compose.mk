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
#      $(eval $(call compose.import, ▰, ↪, docker-compose.yml))
#
#      # example for target dispatch:
#      # a target that runs inside the `debian` container
#      demo: ▰/debian/demo
#      ↪demo:
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
	$(shell if [ "${COMPOSE_MK}" = "0" ]; then cat ${1} | python -c 'import yaml, sys; data=yaml.safe_load(sys.stdin.read()); svc=data["services"].keys(); print(" ".join(svc))'; else echo -n ""; fi)
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
	cat /dev/stdin | pipe=yes make ${relf}/$(compose_service_name)/shell
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

${relf}/%:
	@$$(eval export svc_name:=$$(shell echo $$@|awk -F/ '{print $$$$2}'))
	@$$(eval export cmd:=$(shell echo $${cmd:-}))
	@$$(eval export pipe:=$(shell if [ -z "$${pipe:-}" ]; then echo ""; else echo "-T"; fi))
	@$$(eval export entrypoint:=$(shell if [ -z "$${entrypoint:-}" ]; then echo ""; else echo "--entrypoint $${entrypoint}"; fi))
	@$$(eval export base:=docker compose -f ${compose_file} run --env COMPOSE_MK=1 $${pipe} $${entrypoint} $${svc_name} $${cmd})
	@$$(eval export tmpf:=$$(shell mktemp))
	@if [ -z "$${pipe}" ]; then \
		eval $${base} ; \
	else \
		cat /dev/stdin > "$${tmpf}" \
		&& (printf "$${COLOR_GREEN}→ ${COLOR_DIM}container-dispatch\n  ${NO_COLOR}file=${COLOR_DIM}${COLOR_GREEN}$$(shell basename $${compose_file})${NO_COLOR}\n  service=${COLOR_GREEN}$${svc_name}${NO_COLOR} $${COLOR_DIM}\n `\
				cat $${tmpf} | sed -e 's/COMPOSE_MK=1//' \
			`\n$${NO_COLOR}" >&2)  \
		&& trap "rm -f $${tmpf}" EXIT \
		&& cat "$${tmpf}" | eval $${base} \
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
compose.mktemp:
	export tmpf=`mktemp` \
	&& trap "rm -f $${tmpf}" EXIT \
	&& echo $${tmpf}

compose.wait/%:
	printf "${COLOR_DIM}Waiting for ${*} seconds..${NO_COLOR}\n" > /dev/stderr \
	&& sleep ${*}
compose.indent:
	cat /dev/stdin | sed 's/^/  /'

compose.init:
	@# Ensure compose is available and build it
	docker compose version >/dev/null \
	&& make compose.build

compose.build:
	docker compose build

compose.clean:
	docker compose down --remove-orphans
compose.bash:
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
	@# Sets the given namespace as active.  
	@# Note that this modifies state in the kubeconfig,
	@# and so it can effect contexts outside of the current
	@# process, so this is not thread-safe.
	TERM=xterm kubens ${*} 2>&1 | make compose.indent > /dev/stderr

↪k8s.kubens/%: 
	@# Alias for the top-level target
	TERM=xterm kubens ${*} 2>&1 | make compose.indent > /dev/stderr

k8s.kubens.create/%:
	@# Sets the given namespace as active, creating it if necessary.
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
↪k8s.test_pod_in_namespace/%: 
	make k8s.test_pod_in_namespace/${*}

k8s.namespace/%:
	@# Context-manager.  Activates the given namespace.
	@# (This has side-effects and persists for subprocesses)
	make k8s.kubens/${*}


k8s.namespace.create/%:
	@# Idempotent version of create
	printf '\n' >/dev/stderr 
	kubectl create namespace ${*} \
		--dry-run=client -o yaml \
	| kubectl apply -f - \
	2>&1 | make compose.indent

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
	@# Deletes every matching namespace
	make k8s.namespace.list \
	| grep ${*} \
	|| (\
		printf "${COLOR_DIM}Nothing to purge: no namespaces matching \`${*}*\`${NO_COLOR}\n" \
		> /dev/stderr )\
	| xargs -n1 -I% bash -x -c "make k8s.namespace.purge/%"

k8s.namespace.wait/%:
	@# Waits for every pod in the given namespace to be ready
	@# NB: If the parameter is "all" then this uses --all-namespaces
	export scope=`[ "${*}" == "all" ] && echo "--all-namespaces" || echo "-n ${*}"` \
	&& printf "${COLOR_GREEN}${COLOR_DIM}k8s.namespace.wait/${NO_COLOR}${COLOR_GREEN}${*}${NO_COLOR} :: Looking for pending pods.. \n" > /dev/stderr \
	&& export header="${COLOR_GREEN}${COLOR_DIM}k8s.namespace.wait // ${NO_COLOR}" \
	&& export header="$${header}${COLOR_GREEN}${*}${NO_COLOR}" \
	&& until \
		export tmpf=`make compose.mktemp` \
		&& kubectl get pods $${scope} -o json \
		| jq '[.items[].status.containerStatuses[]|select(.state.waiting)]' \
		> $${tmpf} \
		&& printf "$(strip $(shell cat $${tmpf}|sed -e 's/\[\]//'))" > /dev/stderr \
		&& cat $${tmpf}| jq '.[] | halt_error(length)' \
	; do \
		printf "${COLOR_DIM}`date`${NO_COLOR} Pods aren't ready yet \n" > /dev/stderr \
		&& sleep 3; \
	done \
	&& printf "$${header} :: Namespace looks ready.${NO_COLOR}\n" \
		> /dev/stderr
↪k8s.namespace.wait/%:
	make k8s.namespace.wait/${*}

# Waits until all pods in every namespace are ready
k8s.pods.wait_until_ready: k8s.namespace.wait/all

## END: convenience targets
########################################################################
