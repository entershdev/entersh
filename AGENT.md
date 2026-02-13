# AGENT.md

Instructions for AI agents working on this repository.

## What this repo is

This repo produces two shell scripts (`enter.sh` and `enter-machine.sh`) and a Hugo website. They provide opinionated dev container tooling powered by Podman.

## Repo structure

```
entersh/
├── enter.sh              # Linux dev container script
├── enter-machine.sh      # macOS/Windows dev container script
├── README.md             # Project documentation
├── AGENT.md              # This file
├── LICENSE               # MIT
├── .gitignore
├── .editorconfig
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── site/                 # Hugo website source
│   ├── hugo.toml
│   ├── layouts/
│   ├── static/
│   ├── content/
│   └── public/           # Built output (gitignored)
└── .github/
    ├── ISSUE_TEMPLATE/
    ├── pull_request_template.md
    ├── dependabot.yml
    └── workflows/
        └── pages.yml     # GitHub Pages deployment
```

## Building the website

- Source: `site/`
- Dev server: `cd site && hugo server`
- Build: `cd site && hugo` (output goes to `site/public/`)
- The CI workflow publishes `site/public/` to GitHub Pages on push to main.

## Bundling scripts for release

Scripts ship as-is, no build step required. Create a GitHub Release with a version tag:

```bash
gh release create v1.0.0 enter.sh enter-machine.sh --title "v1.0.0" --notes "Release notes here"
```

The website's curl commands point to `https://github.com/entershdev/entersh/releases/latest/download/`.

## Testing changes to scripts

Verify syntax:

```bash
bash -n enter.sh && bash -n enter-machine.sh
```

Functional test: copy the script to a fresh directory, run it, and verify:

- `Containerfile.dev` is auto-generated.
- Container creates and attaches.
- `--force` recreates the container.
- `--rebuild` rebuilds the image.
- `--verbose` shows full build/create output.

## Volume mount pattern

When adding a dependency that has a cache or config directory:

1. Add the host directory to the `mkdir -p` line in both scripts.
2. Add a `-v` mount line in the `podman run` section of both scripts.
3. Follow the existing pattern documented in the `=== VOLUME MOUNTS ===` comment block.
4. Always update both `enter.sh` and `enter-machine.sh` together.

## Conventions

- Shell: `set -euo pipefail`, quote all variables, use `$()` not backticks.
- Commits: conventional commits format (`feat:`, `fix:`, `docs:`, `chore:`).
- Hugo: content in `site/content/`, layouts in `site/layouts/`.
- No emojis in files.
