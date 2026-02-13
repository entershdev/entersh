# Comparison Section Design

**Date:** 2026-02-13
**Status:** Approved

## Overview

Add a "Why entersh?" section to both README.md and site/layouts/index.html, positioned after "Why Podman?". Philosophy-first paragraph followed by a named comparison table.

## Content Structure

### Philosophy paragraph

entersh is designed for one thing: giving AI coding agents a safe, reproducible place to work. It's a single shell script you drop into a project -- no config language to learn, no platform to install, no YAML to maintain. The folder name is the container name. First run generates a Containerfile.dev if you don't have one. Security hardening is on by default (--cap-drop=all, --read-only, --no-new-privileges). That's it.

### Comparison table

| Tool | Approach | Agent isolation | Config complexity | Nested containers |
|------|----------|----------------|-------------------|-------------------|
| **entersh** | Rootless Podman container | Strong (secure defaults) | Zero config (one script) | Yes (Podman socket) |
| Distrobox | Host-integrated container | None (shares $HOME) | Minimal | Via host-exec |
| Dev Containers | Docker container + JSON spec | Good (needs hardening) | Medium (devcontainer.json) | Yes (DinD feature) |
| Docker Compose | Multi-container orchestration | Moderate | Medium (compose.yaml) | Requires privileges |
| devenv | Nix shell environments | None (no container) | Medium (Nix language) | N/A |
| Vagrant | Full VM | Strongest | Medium (Vagrantfile) | Yes (full kernel) |

### Key differentiators (bullets after table)

- Distrobox shares your entire $HOME by design -- great for GUI apps, wrong for untrusted agents
- Dev Containers are the closest alternative but require a JSON spec, a supporting editor/CLI, and manual security hardening
- Docker Compose is a service orchestrator, not a dev environment tool -- you build the sandbox yourself
- devenv/Nix solve reproducibility brilliantly but provide zero runtime isolation
- Vagrant has the strongest isolation (full VM) but boots in 30-90s and needs gigabytes of RAM

## Placement

- **README.md:** New `## Why entersh?` section after `## Why Podman?`
- **site/layouts/index.html:** New `<section>` after the "Why Podman?" section, before "How it works"

## Approach

Approach A: Separate new section in both files. Philosophy paragraph + comparison table + bullet differentiators.
