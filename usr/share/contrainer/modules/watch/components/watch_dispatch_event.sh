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

  # Loop through all available index scripts given the current event
  while read indexScript; do
    if [ -z "$indexScript" ]; then
      continue
    fi
echo "-----"
    # Run index scripts with every reachable system (host included)
    while read system; do
      # Get the name of the system currently checked
      local systemName="$system"

      if [ "$system" != "%host" ]; then
        systemName="$($TO_HOST docker inspect --format '{{.Name}}' $system 2> /dev/null | sed 's,.*/,,')"
      fi
echo "...$event : $systemName"

      # Get info from the execution of indexScript. What will be returned, is the
      # name of the actual script to run
      local script=$("$indexScript" "$systemName")
      if [ -z "$script" ]; then
        continue
      fi
echo "si... $script"
      # Move the obtained script to host
      local temp=$($TO_HOST mktemp)
      $TO_HOST docker cp $CONTRAINER_ID:"$script" "$temp"
      $TO_HOST chmod +x "$temp"

      # Use a slightly different approach when %host
      if [ "$system" = "%host" ]; then
        # Run the script
echo "in host"
        $TO_HOST sh -c "\
          export CONTRAINER_ID=$CONTRAINER_ID \
          && export CONTRAINER_NAME=$CONTRAINER_NAME \
          && export REGISTRAR_CONTAINER_ID=$triggeringContainerId \
          && export REGISTRAR_CONTAINER_NAME=$triggeringContainerName \
          && export DOCKER_EVENT=$event \
          && $temp"
      else
        # Move the obtained script to container. Notice the several 2> /dev/null
        # Redirections. Must be placed there as there's a chance the target system
        # is not present anymore.
        local temp2=$($TO_HOST docker exec $system mktemp 2> /dev/null)
echo 4
        $TO_HOST docker cp "$temp" $system:"$temp2" 2> /dev/null
echo 5
        $TO_HOST docker exec $system chmod +x "$temp2" 2> /dev/null

        # Run the script
echo 6
echo "$temp2"
        $TO_HOST docker exec $system sh -c "\
          export CONTRAINER_ID=$CONTRAINER_ID \
          && export CONTRAINER_NAME=$CONTRAINER_NAME \
          && export REGISTRAR_CONTAINER_ID=$triggeringContainerId \
          && export REGISTRAR_CONTAINER_NAME=$triggeringContainerName \
          && export DOCKER_EVENT=$event \
          && $temp2" 2> /dev/null

        # Remove the temp file created
echo 7
        $TO_HOST docker exec $system rm "$temp2" 2> /dev/null
      fi

      # Remove the temp file created
      $TO_HOST rm "$temp" 2> /dev/null
    done <<< "$($TO_HOST docker ps --no-trunc -q | sed '$ a %host')"
  done <<< "$(find /var/lib/contrainer/index/*/$event/* -maxdepth 0 -type f -executable 2> /dev/null)"
}

