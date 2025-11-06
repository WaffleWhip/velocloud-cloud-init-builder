# ============================================================
# Module : core.sh
# Purpose: Provide logging, validation helpers, and interactions
# Author : Wahyu Athief (Waf)
# License: MIT
# ============================================================
#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Function : have_tty
# Purpose  : Detect whether an interactive TTY is available
# Params   : None
# Behavior : Returns zero when stdin/stdout/stderr or /dev/tty is a terminal
# Example  : if have_tty; then prompt_value ...; fi
# -----------------------------------------------------------------------------
have_tty() {
  [[ -t 0 ]] || [[ -t 1 ]] || [[ -t 2 ]] || [[ -r /dev/tty ]]
}

# -----------------------------------------------------------------------------
# Function : log_info/log_ok/log_warn/log_err
# Purpose  : Emit colorized log messages for user feedback
# Params   : $1 - message string to display
# Behavior : Writes to stdout using ANSI escape sequences
# Example  : log_info "Starting build"
# -----------------------------------------------------------------------------
log_info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
log_ok()   { echo -e "\033[1;32m[OK]\033[0m $1"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
log_err()  { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

# -----------------------------------------------------------------------------
# Function : tty_print
# Purpose  : Send output directly to the controlling TTY when available
# Params   : $1 - message to print
# Behavior : Falls back to stdout if no TTY is detected
# Example  : tty_print "Enter value:"
# -----------------------------------------------------------------------------
tty_print() {
  if have_tty; then
    printf "%s\n" "$1" > /dev/tty
  else
    printf "%s\n" "$1"
  fi
}

# -----------------------------------------------------------------------------
# Function : prompt_value
# Purpose  : Prompt for user input with optional default and silent entry
# Params   : $1 - prompt text, $2 - default value, $3 - silent flag (0/1)
# Behavior : Returns the entered value or default when empty or non-interactive
# Example  : value=$(prompt_value "Port [8080]: " "8080")
# -----------------------------------------------------------------------------
prompt_value() {
  local prompt="$1"
  local default="${2:-}"
  local silent="${3:-0}"
  local input=""

  if [[ "$PROMPT_MODE" == "off" ]]; then
    echo "$default"
    return
  fi

  if ! have_tty; then
    log_warn "TTY not available for prompt '${prompt//\\n/ }'; using default."
    echo "$default"
    return
  fi

  local tty="/dev/tty"
  if [[ "$silent" == "1" ]]; then
    printf "%s" "$prompt" > "$tty"
    IFS= read -r -s input < "$tty" || true
    printf "\n" > "$tty"
  else
    printf "%s" "$prompt" > "$tty"
    IFS= read -r input < "$tty" || true
  fi

  if [[ -z "$input" ]]; then
    input="$default"
  fi

  echo "$input"
}

# -----------------------------------------------------------------------------
# Function : die
# Purpose  : Terminate execution with an error message and exit code
# Params   : $1 - message, $2 - optional exit code (defaults to 1)
# Behavior : Logs an error and exits the script immediately
# Example  : die "Root privileges required" 2
# -----------------------------------------------------------------------------
die() {
  log_err "$1"
  exit "${2:-1}"
}

# -----------------------------------------------------------------------------
# Function : confirm
# Purpose  : Ask the user to confirm an action via yes/no prompt
# Params   : $1 - question text (defaults to 'Proceed?')
# Behavior : Returns zero when the user confirms, non-zero otherwise
# Example  : if confirm "Continue?"; then ...
# -----------------------------------------------------------------------------
confirm() {
  local prompt="${1:-Proceed?}"
  if [[ "$PROMPT_MODE" == "off" ]]; then
    return 1
  fi
  if ! have_tty; then
    log_warn "TTY not available; defaulting to 'no' for prompt: $prompt"
    return 1
  fi
  local response=""
  printf "%s [y/N]: " "$prompt" > /dev/tty
  IFS= read -r response < /dev/tty || true
  case "${response,,}" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

# -----------------------------------------------------------------------------
# Function : require_command
# Purpose  : Ensure an external command exists before continuing
# Params   : $1 - command name to validate
# Behavior : Exits the script if the command is missing in PATH
# Example  : require_command "pct"
# -----------------------------------------------------------------------------
require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "Required command not found: $cmd"
  fi
}

# -----------------------------------------------------------------------------
# Function : run_safe
# Purpose  : Execute a command while providing contextual logging
# Params   : $1 - description, $2..$n - command and arguments
# Behavior : Logs the description, runs the command, and aborts on failure
# Example  : run_safe "Creating CT" pct create ...
# -----------------------------------------------------------------------------
run_safe() {
  local desc="$1"
  shift
  log_info "$desc"
  if "$@"; then
    log_ok "$desc"
  else
    die "Failed: $desc"
  fi
}

# -----------------------------------------------------------------------------
# Function : shell_quote
# Purpose  : Produce a shell-escaped string for safe inline execution
# Params   : $1 - raw string to escape
# Behavior : Prints a POSIX-compliant escaped version of the string
# Example  : quoted=$(shell_quote "$PASSWORD")
# -----------------------------------------------------------------------------
shell_quote() {
  local str="$1"
  printf '%q' "$str"
}

# -----------------------------------------------------------------------------
# Function : customize_configuration
# Purpose  : Offer interactive overrides for container defaults
# Params   : None (relies on exported global variables)
# Behavior : Prompts the operator to adjust configuration when PROMPT_MODE allows
# Example  : customize_configuration
# -----------------------------------------------------------------------------
customize_configuration() {
  if [[ "$PROMPT_MODE" == "off" ]]; then
    log_info "Skipping interactive customization (PROMPT_MODE=off)"
    return
  fi

  if [[ "$PROMPT_MODE" == "auto" && ! have_tty ]]; then
    log_info "TTY not detected; using defaults. Use CLI flags or environment variables to override."
    return
  fi

  tty_print ""
  tty_print "=== Cloud-Init Builder Interactive Setup ==="
  tty_print "Current defaults:"
  tty_print "  CTID              : $CTID"
  tty_print "  CT Name           : $CTNAME"
  tty_print "  Storage           : $STORAGE"
  tty_print "  Template Storage  : $TEMPLATE_STORAGE"
  tty_print "  Bridge            : $BRIDGE"
  tty_print "  CPU Cores         : $CPU"
  tty_print "  Memory (MB)       : $MEMORY"
  tty_print "  Root Password     : (hidden)"
  tty_print "  WebUI Port        : $PORT"
  tty_print "  Velocloud Version : $VELOCLOUD_VERSION"
  tty_print ""

  local customize="no"
  if [[ "$PROMPT_MODE" == "on" ]]; then
    customize="yes"
  elif confirm "Customize container settings now?"; then
    customize="yes"
  fi

  if [[ "$customize" == "yes" ]]; then
    local value backup

    backup="$CTID"
    value=$(prompt_value "Container ID [$CTID]: " "$CTID")
    CTID="$value"
    if ! [[ "$CTID" =~ ^[0-9]+$ ]]; then
      tty_print "Invalid CTID value. Reverting to $backup."
      CTID="$backup"
    elif (( CTID < MIN_CTID )); then
      tty_print "CTID must be >= $MIN_CTID. Reverting to $backup."
      CTID="$backup"
    fi

    value=$(prompt_value "Container hostname [$CTNAME]: " "$CTNAME")
    [[ -n "$value" ]] && CTNAME="$value"

    value=$(prompt_value "Storage target [$STORAGE]: " "$STORAGE")
    [[ -n "$value" ]] && STORAGE="$value"

    value=$(prompt_value "Template storage [$TEMPLATE_STORAGE]: " "$TEMPLATE_STORAGE")
    [[ -n "$value" ]] && TEMPLATE_STORAGE="$value"

    value=$(prompt_value "Network bridge [$BRIDGE]: " "$BRIDGE")
    [[ -n "$value" ]] && BRIDGE="$value"

    backup="$CPU"
    value=$(prompt_value "CPU cores [$CPU]: " "$CPU")
    if [[ "$value" =~ ^[0-9]+$ ]]; then
      CPU="$value"
    else
      tty_print "Invalid CPU value. Reverting to $backup."
      CPU="$backup"
    fi

    backup="$MEMORY"
    value=$(prompt_value "Memory (MB) [$MEMORY]: " "$MEMORY")
    if [[ "$value" =~ ^[0-9]+$ ]]; then
      MEMORY="$value"
    else
      tty_print "Invalid memory value. Reverting to $backup."
      MEMORY="$backup"
    fi

    backup="$PORT"
    value=$(prompt_value "WebUI port [$PORT]: " "$PORT")
    if [[ "$value" =~ ^[0-9]+$ && "$value" -ge 1 && "$value" -le 65535 ]]; then
      PORT="$value"
    else
      tty_print "Invalid port value. Reverting to $backup."
      PORT="$backup"
    fi

    value=$(prompt_value "Velocloud version [$VELOCLOUD_VERSION]: " "$VELOCLOUD_VERSION")
    [[ -n "$value" ]] && VELOCLOUD_VERSION="$value"

    value=$(prompt_value "Root password (hidden) [$ROOT_PASS]: " "$ROOT_PASS" 1)
    [[ -n "$value" ]] && ROOT_PASS="$value"
  fi

  if [[ -z "$TAILSCALE_KEY" ]]; then
    tty_print ""
    tty_print "Provide a reusable Tailscale auth key to auto-connect this container."
    tty_print "Expected format: tskey-auth-XXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    tty_print "Leave blank to skip auto-join and configure later from the WebUI or shell."
    local key
    key=$(prompt_value "Tailscale auth key: " "")
    if [[ -n "$key" ]]; then
      TAILSCALE_KEY="$key"
      if ! [[ "$TAILSCALE_KEY" =~ ^tskey-auth-[A-Za-z0-9_-]{10,}$ ]]; then
        log_warn "Provided Tailscale auth key does not match the typical tskey-auth- format. Double-check before proceeding."
      fi
    fi
  fi

  tty_print ""
  tty_print "Tip: Prepare a Tailscale API key (format tskey-api-XXXXXXXXXXXXXXXXXXXXXXXXXXXX) for the WebUI"
  tty_print "so the device list can be synchronized once the container is online."
}

# -----------------------------------------------------------------------------
# Function : usage
# Purpose  : Display CLI usage instructions
# Params   : None
# Behavior : Prints supported arguments and exits (caller decides exit code)
# Example  : usage
# -----------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Options:
  --ctid <id>               Container ID (>= $MIN_CTID, default: $DEFAULT_CTID)
  --ctname <name>           Container hostname (default: $DEFAULT_CTNAME)
  --storage <name>          Storage for container rootfs (default: $DEFAULT_STORAGE)
  --template-storage <name> Storage for templates (default: $DEFAULT_TEMPLATE_STORAGE)
  --bridge <bridge>         Network bridge (default: $DEFAULT_BRIDGE)
  --cpu <cores>             CPU cores (default: $DEFAULT_CPU)
  --memory <mb>             Memory in MB (default: $DEFAULT_MEMORY)
  --root-pass <pass>        Root password (default: $DEFAULT_ROOT_PASS)
  --port <port>             WebUI port (default: $DEFAULT_PORT)
  --auth-key <key>          Tailscale auth key for auto-join
  --velocloud-version <ver> Target Velocloud version (default: $DEFAULT_VELOCLOUD_VERSION)
  --prompt                  Force interactive prompts even if defaults exist
  --no-prompt               Disable interactive prompts
  -h, --help                Show this help message

Environment variables with matching names can also override defaults.
EOF
}

# -----------------------------------------------------------------------------
# Function : init_environment
# Purpose  : Prepare runtime context before running the main pipeline
# Params   : None
# Behavior : Launches interactive customization when enabled
# Example  : init_environment
# -----------------------------------------------------------------------------
init_environment() {
  customize_configuration
}
