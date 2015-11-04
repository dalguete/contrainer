# Functionality for the watch_remove_scripts function
#
# Arguments:
#  <container Id>
#   Container Id being affected whom scripts will be removed.

# Used to remove Container contrainer scripts
function watch_remove_scripts() {
  if [ $# -ne 1 ]; then
    die "Container Id expected"
  fi

  local containerId=$1

  rm -rf "/var/lib/contrainer/index/$containerId" 2> /dev/null
  rm -rf "/var/lib/contrainer/scripts/$containerId" 2> /dev/null
}

