# Functionality for the watch_init_scripts function
#
# Arguments:
#  <container Id>
#   Container Id being affected whom scripts should be initialized.

# Used to init Container contrainer scripts
function watch_init_scripts() {
  if [ $# -ne 1 ]; then
    die "Container Id expected"
  fi

  local containerId=$1

  # Trigger the execution of all contrainer scripts found in the triggering container
  local scripts=($($TO_HOST docker exec "$containerId" find /contrainer/ -maxdepth 1 -type f -executable 2> /dev/null | sort))

  # Loop through all scripts obtained, to execute them and process their outputs
  for script in "${scripts[@]}"; do
    local output="$($TO_HOST docker exec "$containerId" "$script" 2> /dev/null)"

    # Invalid Header in contrainer script output is discarded.
    if [[ $(watch_check_header "$output") != 1 ]]; then
      continue
    fi

    # Get the sha of the script
    local scriptSHA="$(echo "$output" | shasum -a 256 | cut -d ' ' -f1)"

    # Get header and rewrite output without it
    local header=$(echo "$output" | head -n 1 | tr -d '[[:space:]]')
    output="$(echo "$output" | tail -n+2)"

    # A blank header is changed to an equivalent explicit definition of it
    if [ -z "$header" ]; then
      header="%me:_inmediate"
    fi
  
    # Register the script.
    mkdir -p "/var/lib/contrainer/scripts/$containerId"
    echo "$output" > "/var/lib/contrainer/scripts/$containerId/$scriptSHA"

    # Triggering scripts (based on header definition) are created to ease script execution discovery
    watch_compile_header "$containerId" "$header" "/var/lib/contrainer/scripts/$containerId/$scriptSHA"
  done
}

