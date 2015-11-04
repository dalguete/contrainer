# Functionality for the watch_compile_header function
#
# Arguments:
#  <container id>
#   Id of the container being analyzed
#
#  <header>
#   Header to compile
#
#  <script file>
#   Path to the contrainer output script to execute when compiled criteria passes

# Used to compile the contrainer script output header
function watch_compile_header() {
  if [ $# -ne 3 ]; then
    die "Expected container Id, header and path to script"
  fi

  # Get all the info
  local containerId="$1"
  local header="$2"
  local scriptPath="$3"

  # Get the container name
  local containerName="$($TO_HOST docker inspect --format '{{.Name}}' $containerId | sed 's,.*/,,')"

  # Set some helpers used to tokenize the header
  local tokenTarget="%me|%contrainer|%host|%all|[a-zA-Z0-9][a-zA-Z0-9_.-]*"
  local tokenTargetOperator="[~+]"
  local tokenEvent="[a-z][a-z_]*"
  local tokenEventSeparator="[:]"
  local tokenSeparator="[,]"

  # Set the regex used to tokenize the whole thing
  local tokenizer="($tokenTarget|$tokenTargetOperator|$tokenEvent|$tokenEventSeparator|$tokenSeparator)"

  # Tokenize the whole header as now we now is valid
  local tokens=()
  local headerHelper="$header"

  # Trick needed as Bash doesn't perform a global regex search, it stops after
  # first match.
  while [[ "$headerHelper" =~ $tokenizer ]]; do
    local item="${BASH_REMATCH[1]}"
    tokens+=("$item")
    headerHelper="${headerHelper#$item}"
  done

  # Add a secure, just for those cases when only one match defined. To avoid having
  # to build the launch script once inside the loop (see below) and another outside
  # of if for the last valid header entry.
  tokens+=(",")

  # Process all tokens obtained
  local mode="container"
  local varName="var$RANDOM"
  local code=
  local containersOp=
  local N=$'\n'
  local eventsList=()
  local defaultEvent="_inmediate"

  for token in "${tokens[@]}"; do
    # Set the work mode and operate on current findings based on the mode set
    if [[ "$token" =~ $tokenSeparator ]]; then
      mode="container"

      # Ensure there's at least the default event
      if [ -z "${eventsList[*]}" ]; then
        eventsList+=("$defaultEvent")
      fi

      # Build the script, one per event
      for event in "${eventsList[@]}"; do
        mkdir -p "/var/lib/contrainer/index/$containerId/$event"
        local scriptName="$RANDOM$RANDOM"
        cat<<EOF > "/var/lib/contrainer/index/$containerId/$event/$scriptName"
#!/usr/bin/env bash
containerName="\${1:-''}"
if [ -z "\$containerName" ]; then
  exit
fi
$code

while read e; do
  if [ "\$e" = "\$containerName" ]; then
    echo "$scriptPath"
    exit
  fi
done <<< "\$$varName"
EOF
  
        # Make the file executable
        chmod +x "/var/lib/contrainer/index/$containerId/$event/$scriptName"
      done

      # Reset
      code=
      containersOp=
      eventsList=()

      continue
    elif [[ "$token" =~ $tokenEventSeparator ]]; then
      mode="event"
      continue
    fi

    # Set the container operation
    if [[ "$token" =~ $tokenTargetOperator ]]; then
      containersOp="$token"
      continue
    fi

    # Consume the tokens based on the mode
    local entry=

    case "$mode" in
      "container")
        # Get the info based on keyword found
        entry="$token"
        if [ "$token" = "%all" ]; then
          entry="\$($TO_HOST docker ps --no-trunc -q | xargs -I {} $TO_HOST docker inspect --format '{{.Name}}' {} | sed 's,.*/,,' | sed '$ a %host')"
        elif [ "$token" = "%me" ]; then
          entry="$containerName"
        elif [ "$token" = "%contrainer" ]; then
          entry="$CONTRAINER_NAME"
        elif [ "$token" = "%host" ]; then
          entry="%host"
        fi

        # Magic happening
        if [ -z "$containersOp" ]; then
          entry="$varName=\"$entry\""
        elif [ "$containersOp" = "~" ]; then
          entry=$(cat<<EOF
while read e; do
  $varName=\$(echo "\$$varName" | sed "/^\$e\$/d")
done <<< "$(echo "$entry")"
EOF
)
        elif [ "$containersOp" = "+" ]; then
          entry=$(cat<<EOF
while read e; do
  $varName="\$$varName${N}\$e"
done <<< "$(echo "$entry")"
EOF
)
        fi

        # Form the code
        code="$code${N}$entry"
        ;;

      "event")
        eventsList+=("$token")
        ;;
    esac
  done
}

