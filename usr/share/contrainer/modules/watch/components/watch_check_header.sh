# Functionality for the watch_check_header function
#
# Arguments:
#  <general content>
#   Output as generated by a contrainer script execution.
#
# Return:
#   1 in case the header is valid, nothing otherwise.

# Used to check the contrainer script output header
function watch_check_header() {
  if [ -z "$*" ]; then
    return
  fi

  # Get the first line (header) to work with. Space is removed from anywhere in that line
  local header=$(echo "$1" | head -n 1 | tr -d '[[:space:]]')

  # In case header is an empty line, is valid
  if [ -z "$header" ]; then
    echo 1
    return
  fi

  # Set some helper checkers used to strip things down
  local tokenTarget="%me|%contrainer|%host|%all|[a-zA-Z0-9][a-zA-Z0-9_.-]*"
  local tokenTargetOperator="[~+]"
  local validTargetSelector="($tokenTarget)(($tokenTargetOperator)($tokenTarget))*"

  local tokenEvent="[a-z][a-z_]*"
  local tokenEventSeparator="[:]"
  local validEventSelector="(($tokenEventSeparator)($tokenEvent))*"

  local validEntry="($validTargetSelector)($validEventSelector)?"

  local tokenSeparator="[,]"
  local validHeader="^($validEntry)(($tokenSeparator)($validEntry))*$"

  # Check is a valid header
  if [[ "$header" =~ $validHeader ]]; then
    echo 1
  fi
}
