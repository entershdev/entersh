# entersh Design Document

**Date:** 2026-02-13
**Status:** Approved

## Overview

entersh provides opinionated dev container scripts for any project, powered by Podman. One script, no YAML, no Compose. Drop `enter.sh` into a project and you have an isolated, reproducible dev environment.

## Core Decisions

- **Approach:** Auto-detect (folder name = container name, no config file)
- **Container runtime:** Podman only (not Docker-compatible, by design)
- **Distribution:** GitHub Releases (scripts as release assets)
- **Website:** Hugo static site on GitHub Pages (local build, CI publishes)
- **License:** MIT
- **GitHub:** github.com/entershdev/entersh

## Scripts

### enter.sh (Linux)

- Auto-detects project name from folder: `PROJECT_NAME="$(basename "$PROJECT_DIR")"`
- Used as container name, image name suffix (`${PROJECT_NAME}-dev`), hostname
- Auto-generates `Containerfile.dev` with sensible defaults if not present (Fedora + common dev tools)
- Rootless Podman with `--userns=keep-id`, `--network=host`
- Mounts Podman socket for nested containers (testcontainers, podman-compose)
- AI-documented volume mount section: clear comments instructing agents to extend mounts when adding dependencies with caches/configs
- Volume mounts: project source, `.container-home/` for persistent caches, `~/.config` (ro), `~/.claude` (rw)
- Lifecycle: create/attach/start, `--force` to recreate, `--rebuild` to rebuild image

### enter-machine.sh (macOS/Windows)

- Same auto-detect and auto-generate behavior
- Uses Podman Machine (VM) instead of native rootless
- Port forwarding (`-p`) instead of `--network=host`
- No `--userns=keep-id` (unreliable through VM layer), fixed container user
- Podman socket from VM at `/run/podman/podman.sock`

## README.md

Structure:
1. Hero section - one-liner pitch
2. Why containers for agents? - isolation, reproducibility, simplicity
3. Why Podman? - rootless by default, no Docker Desktop license, `--userns=keep-id` file permissions, daemonless, nested containers (Podman socket mounted for testcontainers/podman-compose)
4. Quick start - curl from GitHub Releases
5. How it works - lifecycle, folder name detection, auto-generated Containerfile.dev
6. Customizing - Containerfile.dev, volume mounts, ports
7. AGENT.md reference

## AGENT.md

Instructions for AI agents working on this repo:
1. Repo purpose and what it produces
2. Building the Hugo website (`hugo server` for dev, `hugo` to build)
3. Bundling scripts for release (ship as-is)
4. Creating a GitHub Release (tag, attach scripts)
5. Testing changes (run in fresh directory, verify lifecycle)
6. Volume mount pattern (extend when adding dependencies)
7. File structure map

## Hugo Site

- Lives in `site/` directory
- Single landing page with OS-detection JavaScript
- Linux detected: shows `enter.sh` curl command
- macOS/Windows detected: downloads `enter-machine.sh` but saves as `enter.sh`
- Fallback: shows both
- Download URLs point to GitHub Releases latest
- Built locally (`hugo` in `site/`), CI only publishes `site/public/`
- Minimal theme or custom single-page layout

## Open Source Configs

| File | Purpose |
|------|---------|
| `LICENSE` | MIT, copyright entershdev |
| `.gitignore` | `.container-home/`, `site/public/`, OS/editor junk |
| `.editorconfig` | 2-space for YAML/MD, tabs for sh, LF endings |
| `CONTRIBUTING.md` | Fork/branch/PR workflow, code style, testing |
| `CODE_OF_CONDUCT.md` | Contributor Covenant |
| `.github/ISSUE_TEMPLATE/bug_report.md` | Bug report template |
| `.github/ISSUE_TEMPLATE/feature_request.md` | Feature request template |
| `.github/pull_request_template.md` | PR template |
| `.github/dependabot.yml` | Dependabot for GitHub Actions |
| `.github/workflows/pages.yml` | Publish site/public/ to GitHub Pages on push to main |

## Repo Structure

```
entersh/
├── enter.sh
├── enter-machine.sh
├── README.md
├── AGENT.md
├── LICENSE
├── .gitignore
├── .editorconfig
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── site/
│   ├── hugo.toml
│   ├── layouts/
│   ├── static/
│   ├── content/
│   └── public/          (gitignored)
└── .github/
    ├── ISSUE_TEMPLATE/
    │   ├── bug_report.md
    │   └── feature_request.md
    ├── pull_request_template.md
    ├── dependabot.yml
    └── workflows/
        └── pages.yml
```
