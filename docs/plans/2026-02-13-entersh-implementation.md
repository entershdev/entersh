# entersh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the existing app-block-specific container scripts into a generic, distributable open-source project with documentation, a landing page, and standard OSS configs.

**Architecture:** Two shell scripts (enter.sh for Linux, enter-machine.sh for macOS/Windows) that auto-detect the project folder name and use it as the container/image name. A Hugo static site serves as the landing page with OS-aware curl commands. Scripts are distributed via GitHub Releases.

**Tech Stack:** Bash, Podman, Hugo (static site), GitHub Actions (Pages deployment)

---

### Task 1: Foundation — .gitignore and .editorconfig

**Files:**
- Create: `.gitignore`
- Create: `.editorconfig`

**Step 1: Create .gitignore**

```gitignore
# Container state
.container-home/

# Hugo build output
site/public/
site/resources/

# OS junk
.DS_Store
Thumbs.db
*~
*.swp
*.swo

# Editor
.idea/
.vscode/
*.sublime-*
```

**Step 2: Create .editorconfig**

```editorconfig
root = true

[*]
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
charset = utf-8

[*.sh]
indent_style = space
indent_size = 2

[*.{md,yml,yaml,toml,json}]
indent_style = space
indent_size = 2

[Makefile]
indent_style = tab
```

**Step 3: Commit**

```bash
git add .gitignore .editorconfig
git commit -m "Add .gitignore and .editorconfig"
```

---

### Task 2: Foundation — LICENSE, CODE_OF_CONDUCT, CONTRIBUTING

**Files:**
- Create: `LICENSE`
- Create: `CODE_OF_CONDUCT.md`
- Create: `CONTRIBUTING.md`

**Step 1: Create MIT LICENSE**

Standard MIT license text with `Copyright (c) 2026 Troush`.

**Step 2: Create CODE_OF_CONDUCT.md**

Contributor Covenant v2.1 (standard text).

**Step 3: Create CONTRIBUTING.md**

Short guide covering:
- Fork and branch workflow
- How to test changes (run the scripts in a fresh project directory)
- Shell script style: `set -euo pipefail`, quote variables, use `$()` not backticks
- Commit message format: conventional commits style

**Step 4: Commit**

```bash
git add LICENSE CODE_OF_CONDUCT.md CONTRIBUTING.md
git commit -m "Add LICENSE (MIT), CODE_OF_CONDUCT, and CONTRIBUTING guide"
```

---

### Task 3: Generalize enter.sh

**Files:**
- Modify: `enter.sh` (full rewrite of the existing file)

**Step 1: Rewrite enter.sh with these changes:**

1. Replace hardcoded `app-block` with auto-detected folder name:
   ```bash
   PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
   PROJECT_NAME="$(basename "$PROJECT_DIR")"
   IMAGE_NAME="${PROJECT_NAME}-dev"
   CONTAINER_NAME="$PROJECT_NAME"
   ```

2. Add Dockerfile.dev auto-generation function. If `Dockerfile.dev` doesn't exist, generate a default one:
   ```dockerfile
   FROM fedora:latest
   ARG USER_ID=1000
   ARG GROUP_ID=1000
   ARG USER_NAME=dev
   RUN dnf install -y git curl wget make gcc gcc-c++ findutils tar gzip unzip \
       which procps-ng htop tmux bash-completion && dnf clean all
   RUN groupadd -g $GROUP_ID $USER_NAME 2>/dev/null || true && \
       useradd -m -u $USER_ID -g $GROUP_ID -s /bin/bash $USER_NAME
   USER $USER_NAME
   WORKDIR /home/$USER_NAME
   CMD ["/bin/bash"]
   ```

3. Add AI-documented volume mount section with clear instructions:
   ```bash
   # === VOLUME MOUNTS ===
   # AI Agent instructions: When adding a dependency that benefits from persistent
   # caching or configuration, add a volume mount here. Pattern:
   #   1. Create the host directory under .container-home/ (in the mkdir -p line below)
   #   2. Add a -v mount line mapping it to the container path
   #
   # Examples of common additions:
   #   Rust/Cargo:  .container-home/cargo -> ~/.cargo
   #   Python/pip:  .container-home/pip   -> ~/.cache/pip
   #   Maven:       .container-home/m2    -> ~/.m2
   #   Gradle:      .container-home/gradle -> ~/.gradle
   #   Go:          .container-home/go    -> ~/go
   #   Node/npm:    .container-home/npm   -> ~/.npm
   ```

4. Remove app-block-specific volume mounts (Go, npm, opencode). Keep only generic mounts:
   - Project source
   - `.container-home/bash` for bash history
   - `~/.config` (ro) — host editor/tool configs
   - `~/.claude` (rw) — Claude Code auth
   - Podman socket — for nested containers

5. Update header comments to describe entersh generically.

**Step 2: Verify the script is valid bash**

Run: `bash -n enter.sh`
Expected: no output (syntax OK)

**Step 3: Commit**

```bash
git add enter.sh
git commit -m "Generalize enter.sh: auto-detect folder name, auto-generate Dockerfile.dev"
```

---

### Task 4: Generalize enter-machine.sh

**Files:**
- Modify: `enter-machine.sh` (full rewrite of the existing file)

**Step 1: Apply same generalizations as enter.sh:**

1. Auto-detect folder name for PROJECT_NAME, IMAGE_NAME, CONTAINER_NAME
2. Auto-generate Dockerfile.dev if missing (same default Dockerfile)
3. AI-documented volume mount section (same pattern)
4. Remove app-block-specific mounts and hardcoded ports
5. Replace hardcoded `app-block` in all mount paths with `$PROJECT_NAME`
6. Update header comments to describe entersh generically
7. Remove hardcoded port forwarding (`-p 8080:8080` etc.) — leave a commented example block instead

**Step 2: Verify the script is valid bash**

Run: `bash -n enter-machine.sh`
Expected: no output (syntax OK)

**Step 3: Commit**

```bash
git add enter-machine.sh
git commit -m "Generalize enter-machine.sh: auto-detect folder name, auto-generate Dockerfile.dev"
```

---

### Task 5: Write README.md

**Files:**
- Create: `README.md`

**Step 1: Write README.md with these sections:**

1. **Hero** — `# entersh` + one-liner: "One script to give your project a dev container. No YAML. No Compose. Just `enter.sh`."

2. **Why containers for agents?**
   - Isolation: agents can't damage your host
   - Reproducibility: same environment everywhere, Dockerfile is the source of truth
   - Simplicity: one script, not a platform

3. **Why Podman?**
   - Rootless by default — no daemon running as root
   - No Docker Desktop licensing issues
   - `--userns=keep-id` — file permissions just work on Linux
   - Daemonless — each container is its own process
   - Nested containers — Podman socket is mounted into the container, so you can run `podman`, `testcontainers`, or `podman-compose` from inside. No Docker-in-Docker hacks.
   - entersh requires Podman. It is not Docker-compatible.

4. **Quick start**
   - Linux: `curl -fsSL https://github.com/Troush/entersh/releases/latest/download/enter.sh -o enter.sh && chmod +x enter.sh && ./enter.sh`
   - macOS: same but `enter-machine.sh`

5. **How it works**
   - Folder name becomes container and image name
   - Auto-generates Dockerfile.dev if not present
   - Lifecycle: create on first run, attach on subsequent runs
   - `--force` to recreate, `--rebuild` to rebuild image

6. **Customizing**
   - Edit Dockerfile.dev for your stack
   - Volume mounts: follow the pattern in the script comments
   - Ports: add `-p` flags (enter-machine.sh) or use host network (enter.sh)

7. **For AI agents** — see `AGENT.md`

**Step 2: Commit**

```bash
git add README.md
git commit -m "Add README with project pitch and documentation"
```

---

### Task 6: Write AGENT.md

**Files:**
- Create: `AGENT.md`

**Step 1: Write AGENT.md with these sections:**

1. **What this repo is** — "This repo produces two shell scripts (`enter.sh`, `enter-machine.sh`) and a Hugo website. Your job is to maintain them."

2. **Repo structure** — file tree map

3. **Building the website**
   - Source: `site/`
   - Dev server: `cd site && hugo server`
   - Build: `cd site && hugo` (output in `site/public/`)
   - Site is deployed to GitHub Pages by CI when `site/public/` is pushed to main

4. **Bundling scripts for release**
   - Scripts ship as-is, no build step
   - Create a GitHub Release with a version tag (e.g. `v1.0.0`)
   - Attach `enter.sh` and `enter-machine.sh` as release assets:
     ```bash
     gh release create v1.0.0 enter.sh enter-machine.sh --title "v1.0.0" --notes "Release notes here"
     ```

5. **Testing changes to scripts**
   - Create a temporary directory, copy the script into it
   - Run `./enter.sh` — verify it auto-generates Dockerfile.dev
   - Verify container creates, attaches, and destroys with `--force`
   - Check `bash -n enter.sh` and `bash -n enter-machine.sh` for syntax

6. **Volume mount pattern**
   - When adding a dependency with a cache (e.g. Cargo, pip, Maven), extend the volume mounts section in both scripts
   - Follow the documented pattern in the scripts
   - Also add the host directory to the `mkdir -p` line

7. **Conventions**
   - Shell: `set -euo pipefail`, quote all variables, use `$()` not backticks
   - Commits: conventional commits format
   - Hugo: content in `site/content/`, layouts in `site/layouts/`

**Step 2: Commit**

```bash
git add AGENT.md
git commit -m "Add AGENT.md with instructions for AI agents"
```

---

### Task 7: Hugo site setup

**Files:**
- Create: `site/hugo.toml`
- Create: `site/layouts/index.html`
- Create: `site/content/_index.md`
- Create: `site/static/style.css`

**Step 1: Create Hugo config**

`site/hugo.toml`:
```toml
baseURL = "https://troush.github.io/entersh/"
languageCode = "en-us"
title = "entersh"
```

**Step 2: Create the single-page layout**

`site/layouts/index.html` — a complete HTML page (no theme dependency):
- Clean, minimal design
- Hero: project name + tagline
- OS-detection JavaScript that shows the right curl command
- Sections matching README: why containers, why Podman, quick start
- Footer with GitHub link

The JavaScript OS detection:
```javascript
const platform = navigator.platform.toLowerCase();
if (platform.includes('linux')) {
  // Show enter.sh command
} else {
  // Show enter-machine.sh command
}
// Always show toggle to see the other OS command
```

Download URLs: `https://github.com/Troush/entersh/releases/latest/download/enter.sh`

**Step 3: Create minimal content file**

`site/content/_index.md` — front matter only (layout is self-contained):
```yaml
---
title: "entersh"
---
```

**Step 4: Create CSS**

`site/static/style.css` — minimal, clean styling. Monospace font for code blocks, responsive layout, dark/light mode via `prefers-color-scheme`.

**Step 5: Verify Hugo builds**

Run: `cd site && hugo`
Expected: builds to `site/public/` without errors

**Step 6: Commit**

```bash
git add site/
git commit -m "Add Hugo landing page with OS-aware install commands"
```

---

### Task 8: GitHub configs

**Files:**
- Create: `.github/ISSUE_TEMPLATE/bug_report.md`
- Create: `.github/ISSUE_TEMPLATE/feature_request.md`
- Create: `.github/pull_request_template.md`
- Create: `.github/dependabot.yml`
- Create: `.github/workflows/pages.yml`

**Step 1: Create issue templates**

`bug_report.md`:
```markdown
---
name: Bug Report
about: Report a problem with entersh
labels: bug
---

**OS:** (Linux / macOS / Windows WSL2)
**Podman version:** (`podman --version`)

**What happened:**

**What you expected:**

**Steps to reproduce:**
```

`feature_request.md`:
```markdown
---
name: Feature Request
about: Suggest an improvement
labels: enhancement
---

**What problem does this solve?**

**Proposed solution:**
```

**Step 2: Create PR template**

```markdown
## What

## Why

## Testing

- [ ] `bash -n enter.sh` passes
- [ ] `bash -n enter-machine.sh` passes
- [ ] Tested on: (Linux / macOS / both)
```

**Step 3: Create dependabot.yml**

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

**Step 4: Create Pages deployment workflow**

`.github/workflows/pages.yml`:
```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [main]
    paths: [site/public/**]

permissions:
  contents: read
  pages: write
  id-token: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/configure-pages@v4
      - uses: actions/upload-pages-artifact@v3
        with:
          path: site/public
      - id: deployment
        uses: actions/deploy-pages@v4
```

**Step 5: Commit**

```bash
git add .github/
git commit -m "Add GitHub issue templates, PR template, dependabot, and Pages workflow"
```

---

### Task 9: Final verification

**Step 1: Verify all files exist**

Run: `find . -not -path './.git/*' -type f | sort`

Expected file list matches the repo structure from the design doc.

**Step 2: Verify shell scripts are syntactically valid**

Run: `bash -n enter.sh && bash -n enter-machine.sh && echo "OK"`
Expected: `OK`

**Step 3: Verify Hugo builds (if hugo installed)**

Run: `cd site && hugo 2>&1 || echo "Hugo not installed, skip"`

**Step 4: Review git log**

Run: `git log --oneline`
Expected: ~8 commits in logical order, each self-contained.
