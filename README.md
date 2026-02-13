# entersh

Dev containers for AI coding agents. One script, no YAML, no Compose.

Drop `enter.sh` into your project, add your stack and your agent to `Containerfile.dev`, and your agent has a safe, reproducible environment to work in.

## Why containers for agents?

- **Isolation** -- agents running in containers can't accidentally damage your host. If something breaks, destroy the container and recreate it.
- **Reproducibility** -- every agent gets the same environment. The Containerfile is the single source of truth. No "works on my machine."
- **Simplicity** -- one script, not a platform. No Docker Compose, no Kubernetes, no YAML configuration files.

## Why Podman?

- **Rootless by default** -- no daemon running as root, no Docker Desktop license issues.
- **`--userns=keep-id`** -- file permissions between host and container just work on Linux.
- **Daemonless** -- each container is its own process, no central daemon to manage.
- **Nested containers** -- the Podman socket is mounted into the entersh container, so you can run `podman` commands from inside. This enables testcontainers (spin up databases, message queues, etc. in tests), `podman-compose` for multi-service setups, or any workflow that needs to launch containers from within your dev environment. No Docker-in-Docker hacks.

entersh requires Podman. It is not Docker-compatible and does not try to be.

## Why entersh?

entersh is designed for one thing: giving AI coding agents a safe, reproducible place to work. It's a single shell script you drop into a project -- no config language to learn, no platform to install, no YAML to maintain. The folder name is the container name. First run generates a `Containerfile.dev` if you don't have one. Security hardening is on by default (`--cap-drop=all`, `--read-only`, `--no-new-privileges`). That's it.

| Tool | Approach | Agent isolation | Config complexity | Nested containers |
|------|----------|----------------|-------------------|-------------------|
| **entersh** | Rootless Podman container | Strong (secure defaults) | Zero config (one script) | Yes (Podman socket) |
| Distrobox | Host-integrated container | None (shares $HOME) | Minimal | Via host-exec |
| Dev Containers | Docker container + JSON spec | Good (needs hardening) | Medium (devcontainer.json) | Yes (DinD feature) |
| Docker Compose | Multi-container orchestration | Moderate | Medium (compose.yaml) | Requires privileges |
| devenv | Nix shell environments | None (no container) | Medium (Nix language) | N/A |
| Vagrant | Full VM | Strongest | Medium (Vagrantfile) | Yes (full kernel) |

- **Distrobox** shares your entire `$HOME` by design -- great for GUI apps, wrong for untrusted agents.
- **Dev Containers** are the closest alternative but require a JSON spec, a supporting editor/CLI, and manual security hardening.
- **Docker Compose** is a service orchestrator, not a dev environment tool -- you build the sandbox yourself.
- **devenv/Nix** solve reproducibility brilliantly but provide zero runtime isolation.
- **Vagrant** has the strongest isolation (full VM) but boots in 30-90s and needs gigabytes of RAM.

## Quick start

**Linux:**

```bash
curl -fsSL https://github.com/entershdev/entersh/releases/latest/download/enter.sh -o enter.sh
chmod +x enter.sh
./enter.sh
```

**macOS / Windows (WSL2):**

```bash
curl -fsSL https://github.com/entershdev/entersh/releases/latest/download/enter-machine.sh -o enter.sh
chmod +x enter.sh
./enter.sh
```

On first run, entersh generates a default `Containerfile.dev`. Open it and add your project's environment and AI agent:

```dockerfile
# Add your project's language/runtime
RUN dnf install -y golang nodejs python3 ...

# Install your AI coding agent
RUN npm install -g @anthropic-ai/claude-code   # Claude Code
# RUN curl -fsSL https://opencode.ai/install | bash  # Opencode
# RUN npm install -g @anthropic-ai/amp               # Amp
```

Then rebuild: `./enter.sh --rebuild`

## How it works

- The script detects the project name from the folder it's in.
- Folder name = container name = image name (e.g. `myproject/` -> container `myproject`, image `myproject-dev`).
- First run: generates `Containerfile.dev` (if needed), builds the image, creates the container, attaches.
- Subsequent runs: attaches to the existing container (starts it first if stopped).
- `--force`: destroys and recreates the container.
- `--rebuild`: rebuilds the image from `Containerfile.dev`, then recreates the container.
- `--verbose`: shows full build/create output instead of the spinner.

## Customizing

- **Containerfile** -- edit `Containerfile.dev` to add your stack (Go, Node, Python, Rust, etc.).
- **Volume mounts** -- follow the documented pattern in the script to persist caches. The scripts include AI-readable comments explaining how to add mounts for common tools.
- **Ports** -- `enter.sh` uses `--network=host` (all ports accessible). `enter-machine.sh` needs explicit `-p` flags -- add them to the `podman run` command.

## For AI agents

See [AGENT.md](AGENT.md) for instructions on working with this repository.

## Agent-first by design

The scripts are written to be read and modified by AI coding agents. Every section has comments explaining what it does and how to extend it. **Just ask your agent to update `enter.sh` and `Containerfile.dev` for your project -- it will know what to do.**

## License

MIT
