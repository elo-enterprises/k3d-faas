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

# ansi color constants
export NO_ANSI?=\033[0m
export GREEN?=\033[92m
export DIM?=\033[2m
export UNDERLINE?=\033[4m
export BOLD?=\033[1m
export NO_COLOR?=\e[39m
export RED?=\033[91m
export DIM_RED?=${DIM}${RED}
export CYAN?=\033[96m
export DIM_CYAN?=${DIM}${CYAN}
export BOLD_CYAN?=${BOLD}${CYAN}

# Hints for k8s-tools.yml to fix DIND permissions
export DOCKER_UID:=$(shell id -u)
export DOCKER_GID:=$(shell getent group docker | cut -d: -f3 || id -g)
export DOCKER_UGNAME:=user

# honored by `docker compose`, this helps to quiet output
export COMPOSE_IGNORE_ORPHANS?=True

# 1 if dispatched inside container, otherwise 0
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
	$(shell if [ "${COMPOSE_MK}" = "0" ]; then cat ${1} | python3 -c 'import yaml, sys; data=yaml.safe_load(sys.stdin.read()); svc=data["services"].keys(); print(" ".join(svc))'; else echo -n ""; fi)
endef

# Macro to create all the targets for a given compose-service
define compose.create_make_targets
$(eval compose_service_name := $1)
$(eval target_namespace := $2)
$(eval import_to_root := $(strip $3))
$(eval compose_file := $(strip $4))
$(eval namespaced_service:=${target_namespace}/$(compose_service_name))
$(eval compose_file_stem:=$(shell basename -s .yml $(compose_file)))

# Detects the shell
${compose_file_stem}/$(compose_service_name)/__shell__:
	docker compose -f $(compose_file) \
		run --entrypoint sh $$(shell echo $$@|awk -F/ '{print $$$$2}') \
		-c "which bash || which sh" \
		|| printf "$${RED}Neither 'bash' nor 'sh' are available!\n(service=${compose_service_name} @ ${compose_file})\n$${NO_ANSI}" > /dev/stderr

# Invokes the shell
${compose_file_stem}/$(compose_service_name)/shell:
	@export entrypoint=`make ${compose_file_stem}/$(compose_service_name)/__shell__` \
	&& printf "$${GREEN}⇒${NO_ANSI}${DIM} ${compose_file_stem}/$(compose_service_name)/shell (${GREEN}`env|grep entrypoint\=`${NO_ANSI}${DIM})${NO_ANSI}\n" \
		&& make ${compose_file_stem}/$(compose_service_name)
	
${compose_file_stem}/$(compose_service_name)/shell/pipe:
	@$$(eval export tmpf21:=$$(shell mktemp))
	@cat /dev/stdin > $${tmpf21} \
	&& eval "cat $${tmpf21} | pipe=yes \
	  entrypoint=`make ${compose_file_stem}/$(compose_service_name)/__shell__` \
	  make ${compose_file_stem}/$(compose_service_name)"

${compose_file_stem}/$(compose_service_name)/pipe:
	cat /dev/stdin | make ⟂/${compose_file_stem}/$(compose_service_name)

$(eval ifeq ($$(import_to_root), TRUE)
$(compose_service_name): $(target_namespace)/$(compose_service_name)
$(compose_service_name)/pipe: ⟂/${compose_file_stem}/$(compose_service_name)
$(compose_service_name)/shell: ${compose_file_stem}/$(compose_service_name)/shell
$(compose_service_name)/__shell__:  ${compose_file_stem}/$(compose_service_name)/__shell__
$(compose_service_name)/shell/pipe: ${compose_file_stem}/$(compose_service_name)/shell/pipe
endif)

${target_namespace}/$(compose_service_name):
	@# A namespaced target for each docker-compose service
	make ${compose_file_stem}/$$(shell echo $$@|awk -F/ '{print $$$$2}')

${target_namespace}/$(compose_service_name)/%:
	@# A subtarget for each docker-compose service.
	@# This allows invocation of *another* make-target
	@# that runs inside the container
	@echo COMPOSE_MK=1 make $${*} \
		| entrypoint=bash pipe=yes make ${compose_file_stem}/$(compose_service_name)
endef

# Main macro to import services from an entire compose file
define compose.import
$(eval target_namespace:=$1)
$(eval import_to_root := $(if $(2), $(strip $(2)), FALSE))
$(eval compose_file:=$(strip $3))
$(eval compose_file_stem:=$(shell basename -s.yaml `basename -s.yml $(strip ${3}`)))
$(eval __services__:=$(call compose.get_services, ${compose_file}))

⟂/${compose_file_stem}/%:
	@pipe=yes make ${compose_file_stem}/$${*}

${compose_file_stem}/__services__:
	@echo $(__services__)
${compose_file_stem}/__build__:
	set -x && docker compose -f $${compose_file} build
${compose_file_stem}/__stop__:
	docker compose -f $${compose_file} stop -t 1
${compose_file_stem}/__up__:
	docker compose -f $${compose_file} up
${compose_file_stem}/__clean__:
	set -x && docker compose -f $${compose_file} --progress quiet down -t 1 --remove-orphans

${compose_file_stem}/%:
	@$$(eval export svc_name:=$$(shell echo $$@|awk -F/ '{print $$$$2}'))
	@$$(eval export cmd:=$(shell echo $${cmd:-}))
	@$$(eval export pipe:=$(shell \
		if [ -z "$${pipe:-}" ]; then echo ""; else echo "-T"; fi))
	@$$(eval export header:=$${GREEN}⇒${DIM}${NO_COLOR} dispatch: ${GREEN}$${svc_name}${DIM}${NO_COLOR} service, ${BOLD}via ${DIM}${GREEN}$$(shell basename $${compose_file})${NO_ANSI} ${DIM_CYAN}[${NO_ANSI}${BOLD}$(shell \
		if [ -z "$${entrypoint:-}" ]; \
		then echo "default"; else echo "$${entrypoint:-}"; fi)${NO_ANSI}${DIM_CYAN}]${NO_ANSI})
	@$$(eval export entrypoint:=$(shell \
		if [ -z "$${entrypoint:-}" ]; \
		then echo ""; else echo "--entrypoint $${entrypoint:-}"; fi))
	@$$(eval export base:=docker compose -f ${compose_file} \
		run --rm --quiet-pull --env HOME=/tmp --env COMPOSE_MK=1 \
		$${pipe} $${entrypoint} $${svc_name} $${cmd} )
	@$$(eval export tmpf2:=$$(shell mktemp))
	@trap "rm -f $${tmpf2}" EXIT \
	&& if [ -z "$${pipe}" ]; then \
		eval $${base} ; \
	else \
		cat /dev/stdin > $${tmpf2} \
		&& printf "${UNDERLINE}$${header}${NO_ANSI}\n" \
		&& (printf "$${GREEN}⇒${NO_ANSI}${DIM}`cat $${tmpf2} | sed -e 's/COMPOSE_MK=[01] //' |make compose.indent`${NO_ANSI}\n" )  \
		&& cat "$${tmpf2}" | eval $${base} \
	; fi && printf '\n'
$(foreach \
 	compose_service_name, \
 	$(__services__), \
	$(eval \
		$(call compose.create_make_targets, \
			$${compose_service_name}, \
			${target_namespace}, ${import_to_root}, ${compose_file}, )))
endef

## END: macros
########################################################################
## BEGIN: meta targets (api-stable)

help:
	@# Attempts to autodetect the targets defined in this Makefile context.  
	@# Older versions of make dont have '--print-targets', so this uses the 'print database' feature.
	@# See also: https://stackoverflow.com/questions/4219255/how-do-you-get-the-list-of-targets-in-a-makefile
	@#
	@LC_ALL=C $(MAKE) -pRrq -f $(firstword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/(^|\n)# Files(\n|$$)/,/(^|\n)# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | grep -E -v -e '^[^[:alnum:]]' -e '^$@$$' || true

## END: meta targets
########################################################################
## BEGIN: convenience targets (api-stable)
compose.bash:
	@# Drops into an interactive shell with the en vars 
	@# that have been set by the parent environment, 
	@# plus those set by this Makefile context.
	@#
	env bash -l
compose.divider: compose.print_divider
	@# Alias for print_divider

compose.indent:
	@# Pipe-friendly helper for indenting, 
	@# reading from stdin and returning it to stdout.
	@#
	cat /dev/stdin | sed 's/^/  /'

compose.init:
	@# Ensures compose is available.  Note that 
	@# build/run/etc cannot happen without a file, 
	@# for that, see instead targets like '<compose_file_stem>/__build__'
	@#
	docker compose version >/dev/null

compose.mktemp:
	@# Helper for working with temp files.  Returns filename, 
	@# and uses 'trap' to handle at-exit file-deletion automatically
	@#
	export tmpf3=`mktemp` \
	&& trap "rm -f $${tmpf3}" EXIT \
	&& echo $${tmpf3}

compose.print_divider:
	@# Prints a divider on stdout, defaulting to the full terminal width, 
	@# with optional label.  This automatically detects console width, but
	@# it requires 'tput', which is usually part of an ncurses package.
	@#
	@# USAGE: 
	@#  make compose.print_divider label=".." filler=".." width="..."
	@#
	@export width=$${width:-`tput cols`} \
	&& export label=$${label:-} \
	&& if [ -z "$${label}" ]; then \
	    export filler=$${filler:-¯} && printf "%*s$${NO_ANSI}\n" "$${width}" '' | sed "s/ /$${filler}/g"; \
	else \
		export label=" $${label//-/ } " \
	    && export default="#" \
		&& export filler=$${filler:-$${default}} && label_length=$${#label} \
	    && side_length=$$(( ($${width} - $${label_length} - 2) / 2 )) \
	    && printf "%*s" "$${side_length}" | sed "s/ /$${filler}/g" \
		&& printf "$${label}" \
	    && printf "%*s\n" "$${side_length}" | sed "s/ /$${filler}/g" \
	; fi

compose.print_divider/%:
	@# Print a divider with a width of `term_width / <arg>`
	@#
	@# USAGE: 
	@#  make compose.print_divider/<int>
	@#
	@width=`echo \`tput cols\` / ${*} | bc` \
	make compose.print_divider

compose.strip_ansi:
	@# Pipe-friendly helper for stripping ansi.
	@# (Probably won't work everywhere, but has no deps)
	@#
	cat /dev/stdin | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g"'

compose.wait/%:
	@# Pauses for the given amount of seconds.
	@#
	@# USAGE: 
	@#   compose.wait/<int>
	@#
	printf "${DIM}Waiting for ${*} seconds..${NO_ANSI}\n" > /dev/stderr \
	&& sleep ${*}

docker.init:
	@# Checks if docker is available, then displays version (no real setup)
	@#
	docker --version

docker.panic:
	@# Debugging only!  Running this from automation will 
	@# probably quickly hit rate-limiting at dockerhub,
	@# plus you probably don't want to run this in prod.
	@#
	docker rm -f $$(docker ps -qa | tr '\n' ' ')
	docker network prune -f
	docker volume prune -f
	docker system prune -a -f
