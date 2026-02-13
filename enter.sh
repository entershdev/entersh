#!/bin/bash
# enter.sh - Dev container launcher for AI coding agents
#
# Manages a rootless Podman container for development. The container runs with
# host networking and the user's UID/GID (--userns=keep-id) so file permissions
# match the host. The project name and image name are auto-detected from the
# directory containing this script.
#
# If no Containerfile.dev exists, a sensible default is generated automatically.
#
# Usage:
#   ./enter.sh           # Create (first run) or attach to existing container
#   ./enter.sh --force   # Remove and recreate container (keeps image)
#   ./enter.sh --rebuild # Rebuild image from Containerfile.dev, then recreate container
#   ./enter.sh --verbose # Show full podman build/create output (no spinner)
#
# ## How it works
#
# 1. Parse flags (--force, --rebuild)
# 2. If --force/--rebuild: tear down existing container (and image if --rebuild)
# 3. If container already exists:
#    - Running  -> exec into it
#    - Stopped  -> start it, then exec
# 4. If container does not exist:
#    a. Generate Containerfile.dev if missing (Fedora + common dev tools)
#    b. Build image from Containerfile.dev if not present (passes host UID/GID/username)
#    c. Create persistent cache dirs under .container-home/
#    d. Ensure rootless Podman socket is active (needed for nested containers)
#    e. Run container with all volume mounts and env vars
#    f. Exec into it
#
# ## Volume mounts
#
# | Host path                              | Container path                  | Mode | Purpose                         |
# |----------------------------------------|---------------------------------|------|---------------------------------|
# | $PROJECT_DIR                           | ~/$PROJECT_NAME                 | rw   | Project source code             |
# | .container-home/bash                   | ~/.bash_history_dir             | rw   | Persistent bash history         |
# | .container-home/local                  | ~/.local                        | rw   | Tool data (~/.local/share, bin) |
# | .container-home/cache                  | ~/.cache                        | rw   | Tool caches                     |
# | ~/.config                              | ~/.config                       | ro   | Editor/tool configs from host   |
# | ~/.claude                              | ~/.claude                       | rw   | Claude Code auth (if exists)    |
# | $PODMAN_SOCK                           | $PODMAN_SOCK                    | rw   | Podman socket for nested containers |
# | ~/.tmux.conf                           | ~/.tmux.conf                    | ro   | Tmux config from host (if exists) |
#
# ## Environment variables set in container
#
# | Variable      | Purpose                                               |
# |---------------|-------------------------------------------------------|
# | DOCKER_HOST   | Points Docker-compatible clients to Podman socket     |
# | HISTFILE      | Persists bash history to .container-home/bash/        |
#
# ## Container config
#
# - Image: built from Containerfile.dev (Fedora + dev tools by default)
# - --userns=keep-id: maps host UID/GID into container (no permission issues)
# - --network=host: container shares host network (ports, localhost services)
# - --security-opt label=disable: disables SELinux labeling for volume mounts
# - --security-opt no-new-privileges: prevents privilege escalation
# - --cap-drop=all: drops all Linux capabilities (agents don't need them)
# - --read-only: root filesystem is read-only (writes only to mounted volumes and /tmp)
#
# ## Known issues / gotchas
#
# - Podman socket must be running for nested containers to work (auto-started below)
# - .container-home/ is gitignored; deleting it loses cached state and bash history
# - --rebuild is slow because it reinstalls all packages from the Containerfile

set -euo pipefail

# --- Spinner for long-running commands ---
# Usage: run_with_spinner "Label" command [args...]
# Shows a spinner with the last STEP line from podman build, or the label for other commands.
run_with_spinner() {
  local label="$1"
  shift

  # Verbose mode: run directly with full output
  if [ "$VERBOSE" = true ]; then
    echo "$label..."
    "$@"
    return
  fi

  local log pid spin last_step step i
  log=$(mktemp)

  "$@" > "$log" 2>&1 &
  pid=$!
  spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  last_step=""

  while kill -0 "$pid" 2>/dev/null; do
    step=$(grep -o 'STEP [0-9]*/[0-9]*:.*' "$log" 2>/dev/null | tail -1 || true)
    if [ -n "${step:-}" ]; then
      last_step="${step:0:60}"
    fi

    for (( i=0; i<${#spin}; i++ )); do
      if ! kill -0 "$pid" 2>/dev/null; then break; fi
      if [ -n "${last_step:-}" ]; then
        printf "\r  %s %s  " "${spin:$i:1}" "$last_step"
      else
        printf "\r  %s %s  " "${spin:$i:1}" "$label"
      fi
      sleep 0.1
    done
  done

  if wait "$pid"; then
    printf "\r  ✓ %-70s\n" "$label — done."
    rm -f "$log"
  else
    printf "\r  ✗ %-70s\n" "$label — failed!"
    echo ""
    echo "Last 20 lines of output:"
    tail -20 "$log"
    rm -f "$log"
    exit 1
  fi
}

# --- Check if podman is installed ---
if ! command -v podman &>/dev/null; then
  echo "Error: podman is not installed."
  echo ""
  echo "Install podman for your Linux distribution:"
  echo "  Fedora:       sudo dnf install podman"
  echo "  Ubuntu/Debian: sudo apt install podman"
  echo "  Arch:          sudo pacman -S podman"
  echo "  openSUSE:      sudo zypper install podman"
  echo ""
  echo "More info: https://podman.io/docs/installation"
  exit 1
fi

# --- Check if this is the right script for the OS ---
OS="$(uname -s)"
if [ "$OS" != "Linux" ]; then
  echo "Warning: this script is designed for native Linux."
  echo "You are running on $OS."
  echo ""
  echo "Use ./enter-machine.sh instead - it uses podman machine (VM) which"
  echo "is required for macOS and Windows."
  exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
IMAGE_NAME="${PROJECT_NAME}-dev"
CONTAINER_NAME="$PROJECT_NAME"

# --- Parse flags ---
FORCE=false
REBUILD=false
VERBOSE=false
for arg in "$@"; do
  case "$arg" in
  --force) FORCE=true ;;
  --rebuild) REBUILD=true; FORCE=true ;;
  --verbose) VERBOSE=true ;;
  esac
done

# --- Tear down if requested ---
if [ "$FORCE" = true ]; then
  echo "Removing container..."
  podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
  if [ "$REBUILD" = true ]; then
    echo "Rebuilding image..."
    podman rmi -f "$IMAGE_NAME" 2>/dev/null || true
  fi
fi

# --- Check for changes since container was created ---
check_for_changes() {
  local checksums_file="$PROJECT_DIR/.container-home/.checksums"
  if [ ! -f "$checksums_file" ]; then
    return
  fi

  local changed=false
  local containerfile_changed=false

  if [ -f "$PROJECT_DIR/Containerfile.dev" ]; then
    local current_cf
    current_cf="$(sha256sum "$PROJECT_DIR/Containerfile.dev" | cut -d' ' -f1)"
    local saved_cf
    saved_cf="$(grep '^containerfile=' "$checksums_file" 2>/dev/null | cut -d= -f2)"
    if [ -n "$saved_cf" ] && [ "$current_cf" != "$saved_cf" ]; then
      changed=true
      containerfile_changed=true
    fi
  fi

  local current_script
  current_script="$(sha256sum "$0" | cut -d' ' -f1)"
  local saved_script
  saved_script="$(grep '^script=' "$checksums_file" 2>/dev/null | cut -d= -f2)"
  if [ -n "$saved_script" ] && [ "$current_script" != "$saved_script" ]; then
    changed=true
  fi

  if [ "$changed" = true ]; then
    echo ""
    echo "=== Changes detected since container was created ==="
    if [ "$containerfile_changed" = true ]; then
      echo "  Containerfile.dev has changed  -> run: ./enter.sh --rebuild"
    else
      echo "  enter.sh has changed           -> run: ./enter.sh --force"
    fi
    echo "==================================================="
    echo ""
  fi
}

save_checksums() {
  local checksums_file="$PROJECT_DIR/.container-home/.checksums"
  {
    if [ -f "$PROJECT_DIR/Containerfile.dev" ]; then
      echo "containerfile=$(sha256sum "$PROJECT_DIR/Containerfile.dev" | cut -d' ' -f1)"
    fi
    echo "script=$(sha256sum "$0" | cut -d' ' -f1)"
  } > "$checksums_file"
}

# --- Attach to existing container, or create a new one ---
if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
  # Container exists - check for changes then attach or start+attach
  check_for_changes
  if podman inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
    echo "Container '$CONTAINER_NAME' is running, attaching..."
    podman exec -it -w "/home/$(whoami)/$PROJECT_NAME" "$CONTAINER_NAME" /bin/bash
  else
    echo "Container '$CONTAINER_NAME' exists but stopped, starting..."
    podman start "$CONTAINER_NAME"
    podman exec -it -w "/home/$(whoami)/$PROJECT_NAME" "$CONTAINER_NAME" /bin/bash
  fi
else
  # --- Generate Containerfile.dev if missing ---
  if [ ! -f "$PROJECT_DIR/Containerfile.dev" ]; then
    echo "No Containerfile.dev found, generating default..."
    cat > "$PROJECT_DIR/Containerfile.dev" <<'CONTAINERFILE'
FROM fedora:latest
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USER_NAME=dev
RUN dnf install -y git curl wget make gcc gcc-c++ findutils tar gzip unzip \
    which procps-ng htop tmux bash-completion && dnf clean all
RUN groupadd -g $GROUP_ID $USER_NAME 2>/dev/null || true && \
    useradd -m -u $USER_ID -g $GROUP_ID -s /bin/bash $USER_NAME

# ============================================================================
# TODO: Add your project's environment and AI agent below.
#
# 1. Add your project's language/runtime and dependencies:
#    RUN dnf install -y golang nodejs python3 rust cargo ...
#
# 2. Install your AI coding agent (pick one):
#    RUN npm install -g @anthropic-ai/claude-code
#    RUN curl -fsSL https://opencode.ai/install | bash
#    RUN npm install -g @anthropic-ai/amp
#    RUN pip install aider-chat
#    RUN npm install -g @openai/codex
#
# 3. IMPORTANT: Also update enter.sh to mount agent configs from host.
#    Each agent needs its auth/config directory passed through.
#
#    Example — Claude Code:
#      Containerfile.dev:
#        RUN npm install -g @anthropic-ai/claude-code
#      enter.sh (add to OPTIONAL_MOUNTS section):
#        if [ -d "$HOME/.claude" ]; then
#          OPTIONAL_MOUNTS+=(-v "$HOME/.claude:/home/$(whoami)/.claude")
#        fi
#      enter.sh (add to podman run -e flags):
#        -e ANTHROPIC_API_KEY (if you use an API key instead of OAuth)
#
#    Example — Aider:
#      Containerfile.dev:
#        RUN pip install aider-chat
#      enter.sh (add to podman run -e flags):
#        -e OPENAI_API_KEY
#        -e ANTHROPIC_API_KEY
#
# 4. Rebuild the container: ./enter.sh --rebuild
# ============================================================================

USER $USER_NAME
WORKDIR /home/$USER_NAME
CMD ["/bin/bash"]
CONTAINERFILE
  fi

  # --- Build image if missing ---
  if ! podman image exists "$IMAGE_NAME" 2>/dev/null; then
    run_with_spinner "Building image '$IMAGE_NAME'" \
      podman build \
        --build-arg USER_ID="$(id -u)" \
        --build-arg GROUP_ID="$(id -g)" \
        --build-arg USER_NAME="$(whoami)" \
        -t "$IMAGE_NAME" \
        -f "$PROJECT_DIR/Containerfile.dev" \
        "$PROJECT_DIR"
  fi

  # --- Create persistent cache directories ---
  mkdir -p "$PROJECT_DIR/.container-home"/{bash,local,cache}

  # --- Ensure Podman socket is active (required for nested containers) ---
  PODMAN_SOCK="${XDG_RUNTIME_DIR}/podman/podman.sock"
  if [ ! -S "$PODMAN_SOCK" ]; then
    echo "Starting podman socket..."
    systemctl --user start podman.socket
  fi

  # --- Create and start the dev container ---

  # Build optional mount flags
  OPTIONAL_MOUNTS=()
  if [ -f "$HOME/.tmux.conf" ]; then
    OPTIONAL_MOUNTS+=(-v "$HOME/.tmux.conf:/home/$(whoami)/.tmux.conf:ro")
  fi
  if [ -d "$HOME/.config" ]; then
    OPTIONAL_MOUNTS+=(-v "$HOME/.config:/home/$(whoami)/.config:ro")
  fi
  if [ -d "$HOME/.claude" ]; then
    OPTIONAL_MOUNTS+=(-v "$HOME/.claude:/home/$(whoami)/.claude")
  fi

  # === VOLUME MOUNTS ===
  # AI Agent instructions: When adding a dependency that benefits from persistent
  # caching or configuration, add a volume mount here. Pattern:
  #   1. Create the host directory under .container-home/ (in the mkdir -p line above)
  #   2. Add a -v mount line mapping it to the container path
  #
  # Examples of common additions:
  #   Rust/Cargo:  .container-home/cargo  -> ~/.cargo
  #   Python/pip:  .container-home/pip    -> ~/.cache/pip
  #   Maven:       .container-home/m2     -> ~/.m2
  #   Gradle:      .container-home/gradle -> ~/.gradle
  #   Go:          .container-home/go     -> ~/go
  #   Node/npm:    .container-home/npm    -> ~/.npm

  save_checksums

  run_with_spinner "Creating container (first run may take 30-60s for UID remapping)" \
    podman create \
      --name "$CONTAINER_NAME" \
      --hostname "$CONTAINER_NAME" \
      --userns=keep-id \
      --network=host \
      --security-opt label=disable \
      --security-opt no-new-privileges \
      --cap-drop=all \
      --read-only \
      --tmpfs /tmp --tmpfs /var/tmp \
      -v "$PODMAN_SOCK:$PODMAN_SOCK" \
      -e DOCKER_HOST=unix://$PODMAN_SOCK \
      -v "$PROJECT_DIR:/home/$(whoami)/$PROJECT_NAME" \
      -v "$PROJECT_DIR/.container-home/bash:/home/$(whoami)/.bash_history_dir" \
      -v "$PROJECT_DIR/.container-home/local:/home/$(whoami)/.local" \
      -v "$PROJECT_DIR/.container-home/cache:/home/$(whoami)/.cache" \
      -e HISTFILE="/home/$(whoami)/.bash_history_dir/.bash_history" \
      "${OPTIONAL_MOUNTS[@]}" \
      -w "/home/$(whoami)/$PROJECT_NAME" \
      "$IMAGE_NAME" \
      sleep infinity

  podman start "$CONTAINER_NAME" >/dev/null
  podman wait --condition=running "$CONTAINER_NAME" >/dev/null
  podman exec -it -w "/home/$(whoami)/$PROJECT_NAME" "$CONTAINER_NAME" /bin/bash
fi
