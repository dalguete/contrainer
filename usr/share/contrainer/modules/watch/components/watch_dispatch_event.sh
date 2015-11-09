# Functionality for the watch_dispatch_event function
#
# Arguments:
#  <triggering container id>
#   Id of the container that triggered the event
#
#  <event>
#   Name of the event triggered

# Used to dispatch all the scripts in the correct systems, for a given event triggered
function watch_dispatch_event() {
  if [ $# -ne 2 ]; then
    die "Expected triggering container Id and event name"
  fi

  # Get all the info
  local triggeringContainerId="$1"
  local event="$2"

  # Get the name of the container that triggered the event
  local triggeringContainerName="$($TO_HOST docker inspect --format '{{.Name}}' $triggeringContainerId 2> /dev/null | sed 's,.*/,,')"

  # Loop through all available index scripts given the current event. It's important
  # to get only unique scripts (based on the sha name on them) to prevent executing
  # the same script more than once for the current event (see this loop code at the bottom)
  while read indexScript; do
    if [ -z "$indexScript" ]; then
      continue
    fi

    # Run index scripts with every reachable system (host included)
    while read system; do
      # Strip system var components
      local systemName=${system#*:}
      system=${system%%:*}

      # Get info from the execution of indexScript. What will be returned, is the
      # name of the actual script to run
      local script=$("$indexScript" "$systemName" 2> /dev/null)
      if [ -z "$script" ]; then
        continue
      fi

status "$event: $systemName"
      # Move the obtained script to host
      local scriptInHost=$($TO_HOST mktemp)
      # NOTE: Not used the 'docker cp' approach as that was causing errors when
      # finished the container's run process.
#      $TO_HOST docker cp $CONTRAINER_ID:"$script" "$scriptInHost"
      \cp "$script" "$SYSIMAGE/$scriptInHost" 2> /dev/null
      $TO_HOST chmod +x "$scriptInHost"

      # Use a different approach when %host
      if [ "$system" = "%host" ]; then
        # Run the script
        # Environ variables from host system (process 1) are extracted first
        local hostEnviron="$($TO_HOST env - sh -c "xargs -n 1 -0 < /proc/1/environ | xargs -I {} echo export {} \&\&")"

        # As solely nsenter is used to access host, environment needs to be wiped so
        # container's setting won't affect
        $TO_HOST env - sh -c "\
          $hostEnviron
          export CONTRAINER_ID=$CONTRAINER_ID \
          && export CONTRAINER_NAME=$CONTRAINER_NAME \
          && export REGISTRAR_CONTAINER_ID=$triggeringContainerId \
          && export REGISTRAR_CONTAINER_NAME=$triggeringContainerName \
          && export DOCKER_EVENT=$event \
          && $scriptInHost" &> /dev/null
      else
        # NOTE: Originally 'docker exec' was used to execute commands in containers but
        # execution time is much higher than using 'nsenter' directly. Maybe in the
        # future it'll be faster but for now, it's better to use 'nsenter'.

        # Get the container process id
        local systemPid=$($TO_HOST docker inspect --format '{{.State.Pid}}' $system)

        # Move the obtained script to container. Notice the several 2> /dev/null
        # Redirections. Must be placed there as there's a chance the target system
        # is not present anymore.
        local scriptInContainer=$($TO_HOST ${TO_CONTAINER/_/$systemPid} mktemp 2> /dev/null)

        # NOTE: Not used the 'docker cp' approach as that was causing errors when
        # finished the container's run process.
        # Instead, used this https://medium.com/@gchudnov/copying-data-between-docker-containers-26890935da3f
#        $TO_HOST docker cp "$scriptInHost" $system:"$scriptInContainer" 2> /dev/null
        # NOTE2: After some performance tests, 'nsenter' demonstrated to be faster than 'docker exec',
        # so that approach is used instead.
#        $TO_HOST docker exec -i $system sh -c "cat > $scriptInContainer" < "$SYSIMAGE/$scriptInHost" 2> /dev/null
        $TO_HOST ${TO_CONTAINER/_/$systemPid} sh -c "cat > $scriptInContainer" < "$SYSIMAGE/$scriptInHost" 2> /dev/null
        $TO_HOST ${TO_CONTAINER/_/$systemPid} chmod +x "$scriptInContainer" 2> /dev/null

        # Run the script
        $TO_HOST ${TO_CONTAINER/_/$systemPid} sh -c "\
          export CONTRAINER_ID=$CONTRAINER_ID \
          && export CONTRAINER_NAME=$CONTRAINER_NAME \
          && export REGISTRAR_CONTAINER_ID=$triggeringContainerId \
          && export REGISTRAR_CONTAINER_NAME=$triggeringContainerName \
          && export DOCKER_EVENT=$event \
          && $scriptInContainer" &> /dev/null

        # Remove the temp file created
        $TO_HOST ${TO_CONTAINER/_/$systemPid} rm "$scriptInContainer" 2> /dev/null
      fi

      # Remove the temp file created
      $TO_HOST rm "$scriptInHost" 2> /dev/null
    done <<< "$($TO_HOST docker ps --no-trunc -q --format '{{.ID}}:{{.Names}}' | sed '$ a %host:%host')"
  done <<< "$(find /var/lib/contrainer/index/*/$event/* -maxdepth 0 -type f -executable -printf '%f %p'"\n" 2> /dev/null | awk -F" " '!_[$1]++' | cut -d ' ' -f 2)"

  # When the event was 'die', remove all registered scripts for the now dead container.
  if [ "$event" = "die" ]; then
    watch_remove_scripts "$triggeringContainerId"
  fi
}

