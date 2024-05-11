##
# Makefile.compose.mk
#
# This is designed to be used as an `include` inside your project's main Makefile.
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

# Macro to yank all the compose-services out of YAML.  This drops into python unfortunately
# and that's a significant dependency.  But bash or awk would be a nightmare, and 
# even perl requires packages to be installed before it can parse YAML.
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
	@# WARNING: the assert statement is stupid reason to depend on python,
	@#   but it can't be removed easily.  Bash and/or Make will warn of undefined
	@export entrypoint=`docker compose -f $(compose_file) \
		run --entrypoint sh $$(shell python -c"print('$$@'.split('/')[1:][0])") \
		-c "which bash || which sh" \
		2>/dev/null \
		|| printf "$${COLOR_RED}Neither 'bash' nor 'sh' are available!\n(service=${compose_service_name} @ ${compose_file})\n$${NO_COLOR}" > /dev/stderr` \
	&& ( \
		( python -c "import os; assert os.environ['entrypoint'].strip()" &>/dev/null \
			|| exit 1 ) \
		&& make ${relf}/$(compose_service_name) \
	)

${relf}/$(compose_service_name)/shell/pipe:
	pipe=yes \
		make ${relf}/$$(shell python -c"print('$$@'.split('/')[1:][0])")/shell

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
	make ${relf}/$$(shell python -c"print('$$@'.split('/')[1:][0])")

${target_namespace}/$(compose_service_name)/%:
	@# A subtarget for each docker-compose service.
	@# This allows invocation of *another* make-target
	@# that runs inside the container
	@echo COMPOSE_MK=1 make ${dispatch_prefix}$$(shell python -c"print('/'.join('$$@'.split('/')[2:]))") \
		| make ⟫/${relf}/$$(shell python -c"print('$$@'.split('/')[1:][0])")
endef

# Main macro to import services from an entire compose file
define compose.import
$(eval target_namespace:=$1)
$(eval dispatch_prefix:=$2)
$(eval import_to_root := $(if $(3), $(strip $(3)), FALSE))
$(eval compose_file:=$(strip $4))
$(eval relf:=$(shell basename -s .yml $(strip $4)))
$(eval __services__:=$(call compose.get_services, ${compose_file}))

⟫/${relf}/%:
	@entrypoint=bash make ⟂/${relf}/$${*}

⟂/${relf}/%:
	@pipe=yes make ${relf}/$${*}

${relf}/__services__:
	@echo $(__services__)

${relf}/%:
	@$$(eval export svc_name:=$$(shell python -c"print('$$@'.split('/')[1:][0])"))
	@$$(eval export cmd:=$(shell echo $${cmd:-}))
	@$$(eval export pipe:=$(shell if [ -z "$${pipe:-}" ]; then echo ""; else echo "-T"; fi))
	@$$(eval export entrypoint:=$(shell if [ -z "$${entrypoint:-}" ]; then echo ""; else echo "--entrypoint $${entrypoint}"; fi))
	@$$(eval export base:=docker compose -f ${compose_file} run --env COMPOSE_MK=1 $${pipe} $${entrypoint} $${svc_name} $${cmd})
	@$$(eval export tmpf:=$$(shell mktemp))
	@if [ -z "$${pipe}" ]; then \
		eval $${base} ; \
	else \
		cat /dev/stdin > "$${tmpf}" \
		&& (printf "$${COLOR_GREEN}→ ($${svc_name}) $${COLOR_DIM}\n`\
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
## BEGIN: convenience targets (api-unstable: these might change)

compose.wait/%:
	printf "${COLOR_DIM}Waiting for ${*} seconds..${NO_COLOR}\n" > /dev/stderr \
	&& sleep ${*}

compose.init:
	@# Ensure compose is available and build it
	docker compose version >/dev/null \
	&& make compose.build

compose.build:
	@#
	docker compose build

compose.clean:
	@#
	docker compose down --remove-orphans
compose.bash:
	env bash -l

docker.init:
	@# Check if docker is available, no real setup
	@docker --version

docker.panic:
	@# Careful, this is potentially devastating in production..
	docker rm -f $$(docker ps -qa | tr '\n' ' ')
	docker network prune -f
	docker volume prune -f
	docker system prune -a -f

k8s.create.namespace:
	kubectl create namespace $${namespace} \
		--dry-run=client -o yaml \
	| kubectl apply -f -

## END: convenience targets
########################################################################
