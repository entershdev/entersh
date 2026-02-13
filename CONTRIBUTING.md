# Contributing to entersh

## Getting Started

1. Fork the repo
2. Create a feature branch: `git checkout -b my-feature`
3. Make your changes
4. Test locally (see below)
5. Commit and push
6. Open a pull request

## Testing Changes

Test the scripts in a fresh project directory:

```bash
mkdir /tmp/test-project
cp enter.sh /tmp/test-project/
cd /tmp/test-project
./enter.sh              # Should auto-generate Containerfile.dev and create container
./enter.sh              # Should attach to existing container
./enter.sh --force      # Should recreate container
./enter.sh --rebuild    # Should rebuild image and recreate container
```

Verify syntax:

```bash
bash -n enter.sh
bash -n enter-machine.sh
```

## Shell Script Style

- Always use `set -euo pipefail`
- Quote all variables: `"$VAR"` not `$VAR`
- Use `$()` for command substitution, not backticks
- Add comments for non-obvious logic

## Commit Messages

Use conventional commits format:

- `feat: add new feature`
- `fix: fix something broken`
- `docs: update documentation`
- `chore: maintenance tasks`
