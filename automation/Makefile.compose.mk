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
export YELLOW?=\033[33m
export DIM?=\033[2m
export UNDERLINE?=\033[4m
export BOLD?=\033[1m
export ITAL?=\033[3m
export NO_COLOR?=\e[39m
export RED?=\033[91m
export DIM_RED?=${DIM}${RED}
export CYAN?=\033[96m
export DIM_CYAN?=${DIM}${CYAN}
export BOLD_CYAN?=${BOLD}${CYAN}
export BOLD_GREEN?=${BOLD}${GREEN}
export DIM_GREEN:=${DIM}${GREEN}
export DIM_ITAL:=${DIM}${ITAL}
export NO_ANSI_DIM:=${NO_ANSI}${DIM}
export CYAN_FLOW_LEFT:=${BOLD_CYAN}⋘${DIM}⋘${NO_ANSI_DIM}⋘${NO_ANSI}
export GREEN_FLOW_LEFT:=${BOLD_GREEN}⋘${DIM}⋘${NO_ANSI_DIM}⋘${NO_ANSI}
SEP:=${NO_ANSI}//
# Glyphs used in log messages
GLYPH_DOCKER=${GREEN}≣${DIM_GREEN}
GLYPH_IO=${GREEN}⇄${DIM_GREEN}

export OS_NAME:=$(shell uname -s)

# Hints for k8s-tools.yml to fix file permissions
ifeq (${OS_NAME},Darwin)
export DOCKER_UID:=0
export DOCKER_GID:=0
export DOCKER_UGNAME:=root
else 
export DOCKER_UID:=$(shell id -u)
export DOCKER_GID:=$(shell getent group docker 2> /dev/null | cut -d: -f3 || id -g)
export DOCKER_UGNAME:=user
endif

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
	$(shell if [ "${COMPOSE_MK}" = "0" ]; then \
		cat ${1} | python3 -c 'import yaml, sys; data=yaml.safe_load(sys.stdin.read()); svc=data["services"].keys(); print(" ".join(svc))'; \
	else \
		echo -n ""; fi)
endef

# Macro to create all the targets for a given compose-service
define compose.create_make_targets
$(eval compose_service_name := $1)
$(eval target_namespace := $2)
$(eval import_to_root := $(strip $3))
$(eval compose_file := $(strip $4))
$(eval namespaced_service:=${target_namespace}/$(compose_service_name))
$(eval compose_file_stem:=$(shell basename -s .yml $(compose_file)))


${compose_file_stem}/$(compose_service_name)/__shell__:
	@# Detects the best shell to use with ${compose_file_stem}/$(compose_service_name)
	docker compose -f $(compose_file) \
		run --entrypoint sh $$(shell echo $$@|awk -F/ '{print $$$$2}') \
		-c "which bash || which sh" \
		|| printf "${YELLOW}Neither 'bash' nor 'sh' are available!\n(service=${compose_service_name} @ ${compose_file})\n${NO_ANSI}" > /dev/stderr

# Invokes the shell
${compose_file_stem}/$(compose_service_name)/shell:
	@export entrypoint=`make ${compose_file_stem}/$(compose_service_name)/__shell__` \
	&& printf "${GREEN}⇒${NO_ANSI}${DIM} ${compose_file_stem}/$(compose_service_name)/shell (${GREEN}`env|grep entrypoint\=`${NO_ANSI}${DIM})${NO_ANSI}\n" \
		&& make ${compose_file_stem}/$(compose_service_name)
	
${compose_file_stem}/$(compose_service_name)/shell/pipe:
	@$$(eval export shellpipe_tempfile:=$$(shell mktemp))
	@cat /dev/stdin > $${shellpipe_tempfile} \
	&& eval "cat $${shellpipe_tempfile} | pipe=yes \
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
	@echo $(__services__) | sed -e 's/ /\n/g'
${compose_file_stem}/__build__:
	set -x && docker compose -f $${compose_file} build
${compose_file_stem}/__stop__:
	docker compose -f $${compose_file} stop -t 1
${compose_file_stem}/__up__:
	docker compose -f $${compose_file} up
${compose_file_stem}/__clean__:
	set -x && docker compose -f $${compose_file} --progress quiet down -t 1 --remove-orphans
${compose_file_stem}.clean: ${compose_file_stem}/__clean__
${compose_file_stem}.build: ${compose_file_stem}/__build__
${compose_file_stem}/%:
	@$$(eval export svc_name:=$$(shell echo $$@|awk -F/ '{print $$$$2}'))
	@$$(eval export cmd:=$(shell echo $${cmd:-}))
	@$$(eval export pipe:=$(shell \
		if [ -z "$${pipe:-}" ]; then echo ""; else echo "-T"; fi))
	@$$(eval export nsdisp:=${BOLD}$${target_namespace}${NO_ANSI})
	@$$(eval export header:=${GREEN}$${nsdisp}${DIM} ${SEP} ${BOLD}${DIM_GREEN}$${compose_file_stem}${NO_ANSI_DIM} ${SEP} ${BOLD}${GREEN}${UNDERLINE}$${svc_name}${NO_ANSI_DIM} container${NO_ANSI}\n)
	@$$(eval export entrypoint:=$(shell \
		if [ -z "$${entrypoint:-}" ]; \
		then echo ""; else echo "--entrypoint $${entrypoint:-}"; fi))
	@$$(eval export base:=docker compose -f ${compose_file} \
		run --rm --quiet-pull --env COMPOSE_MK=1 \
		$${pipe} $${entrypoint} $${svc_name} $${cmd} )
	@$$(eval export stdin_tempf:=$$(shell mktemp))
	@$$(eval export entrypoint_display:=${CYAN}[${NO_ANSI}${BOLD}$(shell \
			if [ -z "$${entrypoint:-}" ]; \
			then echo "default${NO_ANSI} entrypoint"; else echo "$${entrypoint:-}"; fi)${NO_ANSI_DIM}${CYAN}]${NO_ANSI})
	@$$(eval export cmd_disp:=${NO_ANSI_DIM}${ITAL}`[ -z "$${cmd}" ] && echo " " || echo " $${cmd}\n"`${NO_ANSI})
	
	@trap "rm -f $${stdin_tempf}" EXIT \
	&& if [ -z "$${pipe}" ]; then \
		printf "$${header}${DIM}$${nsdisp} ${NO_ANSI_DIM}$${entrypoint_display}$${cmd_disp}${GREEN_FLOW_LEFT}  ${CYAN}<${NO_ANSI}${BOLD}interactive${NO_ANSI}${CYAN}>${NO_ANSI}${DIM_ITAL}`cat $${stdin_tempf} | sed 's/^[\\t[:space:]]*//'| sed -e 's/COMPOSE_MK=[01] //'`${NO_ANSI}\n" > /dev/stderr \
		&& eval $${base} ; \
	else \
		cat /dev/stdin > $${stdin_tempf} \
		&& printf "$${header}${DIM}$${nsdisp} ${NO_ANSI_DIM}$${entrypoint_display}$${cmd_disp}${CYAN_FLOW_LEFT}  ${DIM_ITAL}`cat $${stdin_tempf} | sed 's/^[\\t[:space:]]*//'| sed -e 's/COMPOSE_MK=[01] //'`${NO_ANSI}\n" > /dev/stderr \
		&& cat "$${stdin_tempf}" | eval $${base} \
	; fi && printf '\n'
$(foreach \
 	compose_service_name, \
 	$(__services__), \
	$(eval \
		$(call compose.create_make_targets, \
			$${compose_service_name}, \
			${target_namespace}, ${import_to_root}, ${compose_file}, )))
endef

help:
	@# Attempts to autodetect the targets defined in this Makefile context.  
	@# Older versions of make dont have '--print-targets', so this uses the 'print database' feature.
	@# See also: https://stackoverflow.com/questions/4219255/how-do-you-get-the-list-of-targets-in-a-makefile
	@#
	@LC_ALL=C $(MAKE) -pRrq -f $(firstword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/(^|\n)# Files(\n|$$)/,/(^|\n)# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | grep -E -v -e '^[^[:alnum:]]' -e '^$@$$' || true

compose.init:
	@# Ensures compose is available.  Note that 
	@# build/run/etc cannot happen without a file, 
	@# for that, see instead targets like '<compose_file_stem>/__build__'
	@#
	docker compose version >/dev/null

docker.init:
	@# Checks if docker is available, then displays version/context (no real setup)
	@#
	set -x && docker --version && docker context show

docker.panic:
	@# Debugging only!  This is good for ensuring a clean environment, 
	@# but running this from automation will nix your cache of downloaded
	@# images, and so you will probably quickly hit rate-limiting at dockerhub.  
	@# It tears down volumes and networks also, so you don't want to run this in prod.
	@#
	docker rm -f $$(docker ps -qa | tr '\n' ' ')
	docker network prune -f
	docker volume prune -f
	docker system prune -a -f

docker.stat:
	@# Show information about docker-status.  No arguments.
	@# This is pipe-friendly, although it also displays additional 
	@# information on stderr for humans, specifically an abbreviated
	@# table for 'docker ps'.  Machine-friendly JSON is also output 
	@# with the following schema:
	@#
	@#   { "version": .., "container_count": .., "socket": .., "context_name": .. }
	@# 
	@#
	$(eval export dstat_tempf:=$$(shell mktemp))
	trap "rm -f ${dstat_tempf}" EXIT \
	&& make docker.context/current > ${dstat_tempf} \
	&& printf "${GLYPH_DOCKER} docker.stat${NO_ANSI_DIM}:\n` \
		docker ps --format "table {{.ID}}\t{{.CreatedAt}}\t{{.Status}}\t{{.Names}}" \
		| make io.print.ident \
	`\n${NO_ANSI}" > /dev/stderr \
	&& echo {} \
		| make io.json.builder key=version \
			val="`docker --version|sed 's/Docker " //'`" \
		| make io.json.builder key=container_count \
			val="`docker ps --format json| jq '.Names'|wc -l`" \
		| make io.json.builder key=socket \
			val="`cat ${dstat_tempf} | jq -r .Endpoints.docker.Host`" \
		| make io.json.builder key=context_name \
			val="`cat ${dstat_tempf} | jq -r .Name`"

docker.context:
	@# Returns all of the available docker context. Pipe-friendly.
	@#
	docker context inspect

docker.context/%:
	@# Returns docker-context details for the given context-name.  
	@# Pipe-friendly; outputs JSON from 'docker context inspect'
	@#
	@# USAGE: (shortcut for the current context name)
	@#  make docker.context/current 
	@#
	@# USAGE: (with given named context)
	@#  docker.context/<context_name>
	@#
	@case "$(*)" in \
		current) \
			make docker.context |  jq ".[]|select(.Name=\"`docker context show`\")" -r; ;; \
		*) \
			make docker.context | jq ".[]|select(.Name=\"${*}\")" -r; ;; \
	esac
	
docker.socket:
	@# Returns the docker socket in use for the current docker context.
	@# No arguments; Pipe-friendly.
	@#
	make docker.context/current | jq -r .Endpoints.docker.Host

docker.stop:
	@# Stops one container, using the given timeout and the given id or name.
	@#
	@# USAGE:
	@#   make docker.stop id=8f350cdf2867 
	@#   make docker.stop name=my-container 
	@#   make docker.stop name=my-container timeout=99
	@#
	printf "${GLYPH_DOCKER} docker.stop${NO_ANSI_DIM} ${SEP} ${GREEN}$${id:-$${name}}${NO_ANSI}\n"
	export cid=`[ -z "$${id:-}" ] && docker ps --filter name=$${name} --format json | jq -r .ID || echo $${id}` \
	&& case "$${cid:-}" in \
		"") \
			printf "$${DIM}${GLYPH_DOCKER} docker.stop${NO_ANSI} // ${YELLOW}No containers found${NO_ANSI}\n"; ;; \
		*) \
			docker stop -t $${timeout:-1} $${cid}; ;; \
	esac

io.bash:
	@# Starts an interactive shell with all the environment variables set 
	@# by the parent environment, plus those set by this Makefile context.
	@#
	env bash -l

io.fmt.strip:
	@# Pipe-friendly helper for stripping whitespace.
	@#
	cat /dev/stdin | awk '{gsub(/[\t\n]/, ""); gsub(/ +/, " "); print}' ORS=''

io.fmt.strip_ansi:
	@# Pipe-friendly helper for stripping ansi.
	@# (Probably won't work everywhere, but has no deps)
	@#
	cat /dev/stdin | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g"'

io.json.builder:
	@# Appends the given key/val to the input object.
	@# This is usually used to build JSON objects from scratch.
	@#
	@# USAGE: 
	@#	 echo {} | key=foo val=bar make io.json.builder 
	@#   {"foo":"bar"}
	@#
	cat /dev/stdin | jq ". + {\"$${key}\": \"$${val}\"}"

io.mktemp:
	@# Helper for working with temp files.  Returns filename, 
	@# and uses 'trap' to handle at-exit file-deletion automatically
	@#
	export c_tempfile=`mktemp` \
	&& trap "rm -f $${c_tempfile}" EXIT \
	&& echo $${c_tempfile}

io.print.dim: 
	@# Pipe-friendly helper for dimming the input text
	@#
	printf "${DIM}`cat /dev/stdin`${NO_ANSI}\n"

io.print.dim.indent:
	@# Like 'io.print.ident' except it also dims the text.
	@#
	cat /dev/stdin | make io.print.dim | make io.print.ident

io.print.divider:
	@# Prints a divider on stdout, defaulting to the full terminal width, 
	@# with optional label.  This automatically detects console width, but
	@# it requires 'tput' (usually part of a 'ncurses' package).
	@#
	@# USAGE: 
	@#  make io.print.divider label=".." filler=".." width="..."
	@#
	@export width=$${width:-`tput cols`} \
	&& label=$${label:-} \
	&& if [ -z "$${label}" ]; then \
	    filler=$${filler:-¯} && printf "%*s${NO_ANSI}\n" "$${width}" '' | sed "s/ /$${filler}/g"; \
	else \
		label=" $${label//-/ } " \
	    && default="#" \
		&& filler=$${filler:-$${default}} && label_length=$${#label} \
	    && side_length=$$(( ($${width} - $${label_length} - 2) / 2 )) \
	    && printf "%*s" "$${side_length}" | sed "s/ /$${filler}/g" \
		&& printf "$${label}" \
	    && printf "%*s\n" "$${side_length}" | sed "s/ /$${filler}/g" \
	; fi

io.print.divider/%:
	@# Print a divider with a width of `term_width / <arg>`
	@#
	@# USAGE: 
	@#  make io.print.divider/<int>
	@#
	@width=`echo \`tput cols\` / ${*} | bc` \
	make io.print.divider

io.print.ident:
	@# Pipe-friendly helper for indention; reads from stdin and returns indented result on stdout
	@#
	cat /dev/stdin | sed 's/^/  /'

io.time.wait/%:
	@# Pauses for the given amount of seconds.
	@#
	@# USAGE: 
	@#   io.time.wait/<int>
	@#
	printf "${GLYPH_IO} io.wait${NO_ANSI} ${SEP} ${DIM}Waiting for ${*} seconds..${NO_ANSI}\n" > /dev/stderr \
	&& sleep ${*}

io.time.target/%:
	@# Emits run time for the given make-target in seconds.
	@# Pipe safe; target's stdout is sent to stderr.
	@#
	@# USAGE:
	@#   io.time.target/<target_to_run>
	@#
	start_time=$$(date +%s%N) \
	&& make ${*} >&2 \
	&& end_time=$$(date +%s%N) \
	&& time_diff_ns=$$((end_time - start_time)) \
	&& echo $$(echo "scale=9; $$time_diff_ns / 1000000000" | bc)
io.time.wait_for_command:
	@# Runs the given command for the given amount of seconds, then stops it with SIGINT.
	@#
	@# USAGE: (tails docker logs for up to 10s, then stops)
	@#   make io.time.wait_for_command cmd='docker logs -f xxxx' timeout=10
	@#
	printf "${GLYPH_IO} io.time.wait_for_command${NO_ANSI_DIM} (${YELLOW}$${timeout}s${NO_ANSI_DIM}) ${SEP} ${NO_ANSI_DIM}$${cmd}${NO_ANSI} ${NO_ANSI}\n" >/dev/stderr 
	trap "pkill -SIGINT -f \"$${cmd}\"" INT \
	&& eval "$${cmd} &" \
	&& export command_pid=$$! \
	&& sleep $${timeout} \
	&& printf "${DIM}${GLYPH_IO} io.time.wait_for_command${NO_ANSI_DIM} (${YELLOW}$${timeout}s${NO_ANSI_DIM}) ${SEP} ${NO_ANSI}${YELLOW}finished${NO_ANSI}\n" >/dev/stderr \
	&& kill -INT $${command_pid}

