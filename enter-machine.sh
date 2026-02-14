#!/bin/bash
# enter-machine.sh - Dev container launcher for AI coding agents (macOS/Windows via Podman Machine)
#
# Cross-platform alternative to enter.sh. Uses `podman machine` which runs a
# Linux VM under the hood (QEMU on Mac, WSL2 on Windows). All container
# operations happen inside that VM.
#
# The project name and image name are auto-detected from the directory
# containing this script. If no Containerfile.dev exists, a sensible default
# is generated automatically.
#
# Prerequisites:
#   - Podman Desktop installed (https://podman-desktop.io) or `brew install podman`
#   - On first use, run: podman machine init && podman machine start
#
# Usage:
#   ./enter-machine.sh           # Create (first run) or attach to existing container
#   ./enter-machine.sh --force   # Remove and recreate container (keeps image)
#   ./enter-machine.sh --rebuild # Rebuild image from Containerfile.dev, then recreate
#   ./enter-machine.sh --verbose # Show full podman build/create output (no spinner)
#
# ## Differences from enter.sh (native Linux)
#
# | Feature              | enter.sh (Linux)              | enter-machine.sh (Mac/Windows)       |
# |----------------------|-------------------------------|--------------------------------------|
# | Container runtime    | Rootless Podman directly      | Podman Machine (Linux VM)            |
# | Network              | --network=host (real host)    | Port forwarding (-p flags)           |
# | UID mapping          | --userns=keep-id              | Fixed UID 1000 (VM user)             |
# | Podman socket        | systemctl --user              | Managed by podman machine            |
# | SELinux              | --security-opt label=disable  | Not applicable                       |
# | Volume performance   | Native filesystem             | virtiofs (Mac) / 9p (older). Slower  |
#
# ## How it works
#
# 1. Verify podman machine is running (start it if not)
# 2. Parse flags (--force, --rebuild)
# 3. If container already exists: attach or start+attach
# 4. If container does not exist:
#    a. Generate Containerfile.dev if missing (Fedora + common dev tools)
#    b. Build image from Containerfile.dev (UID 1000 default - VM user)
#    c. Create persistent cache dirs under .container-home/
#    d. Run container with port forwarding and volume mounts
#    e. Exec into it
#
# ## Volume mounts
#
# On Mac, $HOME is shared with the VM by default via virtiofs.
# On Windows (WSL2), /mnt/c/Users/... paths are available.
# All project paths must be under the shared mount to work.
#
# | Host path                              | Container path                  | Mode | Purpose                         |
# |----------------------------------------|---------------------------------|------|---------------------------------|
# | $PROJECT_DIR                           | ~/$PROJECT_NAME                 | rw   | Project source code             |
# | .container-home/bash                   | ~/.bash_history_dir             | rw   | Persistent bash history         |
# | .container-home/local                  | ~/.local                        | rw   | Tool data (~/.local/share, bin) |
# | .container-home/cache                  | ~/.cache                        | rw   | Tool caches                     |
# | ~/.config                              | ~/.config                       | ro   | Editor/tool configs from host   |
# | ~/.claude                              | ~/.claude                       | rw   | Claude Code auth (if exists)    |
# | ~/.tmux.conf                           | ~/.tmux.conf                    | ro   | Tmux config from host (if exists) |
#
# ## Ports
#
# No ports are forwarded by default. Add port forwarding as needed in the
# podman run command below (see commented examples).
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
# - Fixed container user "dev" (UID 1000) - --userns=keep-id is unreliable through VM layer
# - Port forwarding (-p) instead of --network=host (VM network is not the host)
# - No SELinux flags (not applicable on Mac/Windows)
# - Podman socket from VM (auto-detected via podman info)
# - --security-opt no-new-privileges: prevents privilege escalation
# - --cap-drop=all: drops all Linux capabilities (agents don't need them)
# - --read-only: root filesystem is read-only (writes only to mounted volumes and /tmp)
#
# ## Known issues / gotchas
#
# - Volume mounts through virtiofs are slower than native Linux. Builds and
#   downloads will be noticeably slower on first run.
# - podman machine must be initialized once: `podman machine init --cpus 4 --memory 4096`
# - On Mac, if ports conflict: `podman machine stop && podman machine start` to reset
# - Container user is "dev" (UID 1000) because --userns=keep-id doesn't reliably
#   map host Mac/Windows UIDs. Containerfile.dev defaults handle this.
# - If you see "permission denied" on mounted volumes, check that your project
#   directory is under a path shared with the podman machine (default: $HOME)
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
  OS="$(uname -s)"
  echo "Error: podman is not installed."
  echo ""
  if [ "$OS" = "Darwin" ]; then
    echo "Install podman on macOS:"
    echo "  brew install podman"
    echo "  OR install Podman Desktop: https://podman-desktop.io"
  elif grep -qi microsoft /proc/version 2>/dev/null; then
    echo "Install podman on Windows (WSL2):"
    echo "  Install Podman Desktop: https://podman-desktop.io"
    echo "  OR in WSL2: sudo apt install podman"
  else
    echo "Install podman:"
    echo "  https://podman.io/docs/installation"
  fi
  exit 1
fi

# --- Check if this is the right script for the OS ---
OS="$(uname -s)"
if [ "$OS" = "Linux" ] && ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "Warning: you are on native Linux."
  echo ""
  echo "Use ./enter.sh instead - it runs rootless Podman directly without a VM,"
  echo "which is faster and uses --network=host and --userns=keep-id."
  echo ""
  echo "Only use this script if you specifically need podman machine."
  echo "Continue anyway? [y/N]"
  read -r answer
  if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    exit 0
  fi
fi

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
IMAGE_NAME="${PROJECT_NAME}-dev"
CONTAINER_NAME="$PROJECT_NAME"
CONTAINER_USER="dev"

# Socket path inside the podman machine VM (detect from podman info)
PODMAN_SOCK="$(podman info --format '{{.Host.RemoteSocket.Path}}' 2>/dev/null | sed 's|^unix://||')"
if [ -z "$PODMAN_SOCK" ]; then
  PODMAN_SOCK="/run/podman/podman.sock"
fi

# --- Ensure podman machine is running ---
if ! podman machine inspect 2>/dev/null | grep -q '"State": "running"'; then
  echo "Podman machine is not running."
  if podman machine inspect 2>/dev/null | grep -q '"Name"'; then
    echo "Starting podman machine..."
    podman machine start
  else
    echo "No podman machine found. Initializing..."
    podman machine init --cpus 4 --memory 4096
    podman machine start
  fi
fi

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
      echo "  Containerfile.dev has changed     -> run: ./enter-machine.sh --rebuild"
    else
      echo "  enter-machine.sh has changed   -> run: ./enter-machine.sh --force"
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
    podman exec -it -w "/home/$CONTAINER_USER/$PROJECT_NAME" "$CONTAINER_NAME" /bin/bash
  else
    echo "Container '$CONTAINER_NAME' exists but stopped, starting..."
    podman start "$CONTAINER_NAME"
    podman exec -it -w "/home/$CONTAINER_USER/$PROJECT_NAME" "$CONTAINER_NAME" /bin/bash
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
  # Use UID/GID 1000 as default - podman machine VM user
  if ! podman image exists "$IMAGE_NAME" 2>/dev/null; then
    run_with_spinner "Building image '$IMAGE_NAME'" \
      podman build \
        --build-arg USER_ID=1000 \
        --build-arg GROUP_ID=1000 \
        --build-arg USER_NAME="$CONTAINER_USER" \
        -t "$IMAGE_NAME" \
        -f "$PROJECT_DIR/Containerfile.dev" \
        "$PROJECT_DIR"
  fi

  # --- Create persistent cache directories ---
  mkdir -p "$PROJECT_DIR/.container-home"/{bash,local,cache}

  # --- Create and start the dev container ---
  # Key differences from enter.sh:
  #   - No --userns=keep-id (unreliable through VM layer)
  #   - No --network=host (means VM network, not Mac/Windows host)
  #   - Port forwarding instead (-p)
  #   - No SELinux flags (not applicable)
  #   - Podman socket from VM, not host systemd
  #   - Fixed container user "dev" (UID 1000)

  # Build optional mount flags
  OPTIONAL_MOUNTS=()
  [ -f "$HOME/.tmux.conf" ] && OPTIONAL_MOUNTS+=(-v "$HOME/.tmux.conf:/home/$CONTAINER_USER/.tmux.conf:ro")
  [ -d "$HOME/.config" ] && OPTIONAL_MOUNTS+=(-v "$HOME/.config:/home/$CONTAINER_USER/.config:ro")
  [ -d "$HOME/.claude" ] && OPTIONAL_MOUNTS+=(-v "$HOME/.claude:/home/$CONTAINER_USER/.claude")

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

  # Add port forwarding as needed, e.g.:
  #   -p 8080:8080 \
  #   -p 3000:3000 \

  save_checksums

  run_with_spinner "Creating container '$CONTAINER_NAME'" \
    podman create \
      --name "$CONTAINER_NAME" \
      --hostname "$CONTAINER_NAME" \
      --security-opt no-new-privileges \
      --cap-drop=all \
      --read-only \
      --tmpfs /tmp --tmpfs /var/tmp \
      -v "$PODMAN_SOCK:$PODMAN_SOCK" \
      -e DOCKER_HOST=unix://$PODMAN_SOCK \
      -e HISTFILE="/home/$CONTAINER_USER/.bash_history_dir/.bash_history" \
      -v "$PROJECT_DIR:/home/$CONTAINER_USER/$PROJECT_NAME" \
      -v "$PROJECT_DIR/.container-home/bash:/home/$CONTAINER_USER/.bash_history_dir" \
      -v "$PROJECT_DIR/.container-home/local:/home/$CONTAINER_USER/.local" \
      -v "$PROJECT_DIR/.container-home/cache:/home/$CONTAINER_USER/.cache" \
      "${OPTIONAL_MOUNTS[@]}" \
      -w "/home/$CONTAINER_USER/$PROJECT_NAME" \
      "$IMAGE_NAME" \
      sleep infinity

  podman start "$CONTAINER_NAME" >/dev/null
  podman wait --condition=running "$CONTAINER_NAME" >/dev/null
  podman exec -it -w "/home/$CONTAINER_USER/$PROJECT_NAME" "$CONTAINER_NAME" /bin/bash
fi
