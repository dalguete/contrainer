# Main functionality for the watch function
#
# Operation must be registerd with "set_operation"
# Internal process requires some functions to be defined, as explained next
# 
#   <OPERATION>_usage
#     Used when usage message should be displayed for the operation defined.
# 
#   <OPERATION>_consume
#     Used when the operation options should be consumed.
# 
# Be sure to implement them.
# 

set_operation "watch" "" ""

# Function used to display operation usage
function watch_usage() {
  die "TODO: Watch usage"
}

# Function used to consume operation passed options
function watch_consume() {
  # As nothing is consumed, simply do nothing
  :

#  # Process all input data. Only valid entries will live here. Non valid ones are
#  # filtered in the main consume process
#  while [ $# -gt 0 ]
#  do
#    case "$1" in
#      -o|--option-long) # Indicates <something>
#        set_option "<key>" "$2"
#        shift
#        ;;
#    esac
#
#    shift
#  done
}

# Function used to watch for Docker events being triggered
#
# Operation:
#   watch
#
# Arguments:
#  N/A
# 
# Return:
#   Prints the Docker events as they are consumed, and inform about scripts execution.
#   Keeps printing, unless terminated.
function watch() {
  # Continuously read the events as they arrive. The output buffer is disabled explicitly,
  # as there's no certainty on what 'docker events' does. It seems works fine, but
  # just in case.
  $TO_HOST stdbuf -o0 docker events | while read line
  do
    local parts=()
    local event=

    # Extract the event name from log line
    read -a parts <<< "$line"
    when="$(echo "${parts[0]}" | sed -e 's/\:$//')"
    event="$(echo "${parts[-1]}" | sed -e 's/\:$//')"

    # Extract parts from log line based on triggering event
    #
    # Based on https://github.com/docker/docker/blob/master/docs/reference/commandline/events.md
    case "$event" in
      "attach" | "commit" | "copy" | "create" | "destroy" | "die" | "exec_create" | "exec_start" | "export" | "kill" | "oom" | "pause" | "rename" | "resize" | "restart" | "start" | "stop" | "top" | "unpause" )
        local containerId="$(echo "${parts[1]}" | sed -e 's/\:$//')"
        local imageId="$(echo "${parts[3]}" | sed -e 's/)$//')"

        # Reaching the 'Create' event means start collecting
        if [ "$event" = "create" ]; then
          set_option "container_${containerId}_collect" "$containerId"
          set_option "container_${containerId}_events" "_inmediate" 1
        fi

        # Reaching the 'Start' event means init scripts and start consuming collected events
        if [ "$event" = "start" ]; then
          # Init scripts
          watch_init_scripts "$containerId"

          # Consume enqueued events
          while IFS= read e; do
            watch_dispatch_event "$containerId" "$e"
            remove_option "container_${containerId}_events" "$e"
          done <<< "$(get_options "container_${containerId}_events")"

          # Remove the option set to start collecting
          remove_option "container_${containerId}_collect" "$containerId"
        fi
  
        # Check the container has been marked to collect.
        if [ $(is_option "container_${containerId}_collect" "$containerId") -eq 1 ]; then
          set_option "container_${containerId}_events" "$event" 1
          continue
        fi

        # Dispatch the current event
        watch_dispatch_event "$containerId" "$event"
        ;;

      "delete" | "import" | "pull" | "push" | "tag" | "untag" )
        local imageId="$(echo "${parts[1]}" | sed -e 's/\:$//')"
        ;;
    esac
  done
}

