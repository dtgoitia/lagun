# CLAUDE.md

## Project Overview

`lagun` is a reusable project template for safe agentic and non-agentic Python development, built on Nix flakes for full reproducibility.

## Architecture

### Two Modes of Operation

**Developer mode (non-agentic):** Run `./dev` at the project root. This calls `nix develop --command $SHELL`, preserving your host shell (fish, bash, zsh, etc.) and all host environment variables. The shell hook creates `.venv` if missing, syncs dependencies via `uv sync`, and activates the virtual environment.

**Agent mode (agentic):** Claude Code runs inside a Podman container. The workspace is mounted as a volume. No virtual environment — Python runs directly from the Nix-provided interpreter.

### Credentials

- **Developer mode:** `varlock` injects real secrets as environment variables.
- **Agent mode:** `varlock` injects dummy/fake secrets. `OneCLI` runs as a side container, intercepts all outgoing HTTP traffic via `HTTP_PROXY`/`HTTPS_PROXY`, and swaps dummy secrets for real ones in-flight.

## varlock

- Source: [dmno-dev/varlock](https://github.com/dmno-dev/varlock) — must be wrapped in a Nix flake (not in nixpkgs)
- Claude Code skill: [wrsmith108/varlock-claude-skill](https://github.com/wrsmith108/varlock-claude-skill)
- Secret variable names: TBD — to be defined once secrets are known (see `questions.md`)

## Repository Structure

```
.
├── flake.nix              # Nix flake — pins Python 3.13, uv, pre-commit, alejandra, all dev tools
├── pyproject.toml         # Python project metadata and tool configuration
├── .pre-commit-config.yaml
├── dev                    # Executable wrapper: runs `nix develop --command $SHELL`
├── compose.yml            # Podman Compose — agent + OneCLI containers
├── CLAUDE.md              # This file
└── src/lagun/             # src layout — package root
```

## Nix Flake

- Channel: `nixos-unstable`
- Python: pinned to 3.13, managed entirely by Nix
- `uv` manages dependency resolution and installation; Nix manages the interpreter
- The flake is designed for later NixOS VPS deployment — keep it container-friendly
- Supported systems: `x86_64-linux`, `aarch64-linux`

## Developer Shell (`nix develop` / `./dev`)

- Entry point: `./dev` — runs `nix develop --command $SHELL`
- The `shellHook` does **not** switch shells or execute commands directly
- On enter:
  1. Creates `.venv` if it does not exist
  2. Runs `uv sync` to install/sync dependencies (set `SKIP_UV_SYNC=1` on the host to bypass)
  3. Activates `.venv`

## Git Hooks

Hooks are managed by [`git-hooks.nix`](https://github.com/cachix/git-hooks.nix) (`github:cachix/git-hooks.nix`), declared directly in `flake.nix`. No `.pre-commit-config.yaml` file — all hook config lives alongside the Nix package pins. Entering the dev shell via `nix develop` / `./dev` installs the hooks into `.git/hooks/` automatically.

| Hook | Tool |
|------|------|
| File ends with newline | `end-of-file-fixer` |
| Markdown formatting | `prettier` (via Nix) |
| Nix formatting | `alejandra` |
| Python linting/formatting | `ruff` |
| Python type checking | `ty` (Astral — custom hook if not built-in) |
| Python tests | `pytest` via `uv run pytest` (custom hook) |

## Agent Container

- Base: pure NixOS image via `pkgs.dockerTools.buildLayeredImage`
- Orchestration: Podman Compose (`compose.yml`)
- Run with: `--userns=keep-id`
- Container user: `lagun`
- Workspace mount: host project root → `/home/lagun/workspace`
- Auth persistence: host `~/.config/claude-code` mounted into `/home/lagun/.config/claude-code`
- Image contents: Python 3.13, `uv`, Claude Code — no extra tools; keep the image minimal
- Claude Code: baked into the image via Nix, pinned with `prefetch-npm-deps`
- No CPU or memory resource limits

### OneCLI Side Container

- Image: `ghcr.io/onecli/onecli:1.36`
- Configuration: environment variables only — all config passed via `environment:` in `compose.yml`
- Shares a named volume `onecli_certs` for the CA certificate bundle
- Agent container sets `NODE_EXTRA_CA_CERTS` to trust the OneCLI CA
- Agent container sets `HTTP_PROXY`/`HTTPS_PROXY` to route traffic through OneCLI
- Agent container waits for OneCLI to be healthy before starting

## Updating Claude Code

To update the Claude Code version pinned in the Nix flake:
1. Find the new version on npmjs.com or the Claude Code release page
2. Run `nix run nixpkgs#prefetch-npm-deps` with the new package tarball URL to obtain the new hash
3. Update the version string and hash in `flake.nix`

## Key Constraints

- No database
- No CI/CD
- IDE agnostic — no editor-specific config files
- Linux only (`x86_64-linux`, `aarch64-linux`)
- Do not use virtual environments inside the agent container
- Do not use `--no-verify` to skip pre-commit hooks — fix the underlying issue instead
