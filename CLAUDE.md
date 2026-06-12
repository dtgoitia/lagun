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

- Source: [dmno-dev/varlock](https://github.com/dmno-dev/varlock) — npm monorepo CLI (`varlock` v1.6.1), no `flake.nix`
- Packaged in Nix via `fetchurl` + `stdenv.mkDerivation` using pre-built musl Linux binaries from GitHub releases
- Claude Code skill: [wrsmith108/varlock-claude-skill](https://github.com/wrsmith108/varlock-claude-skill) — baked into the agent image at `/home/lagun/.claude/skills/varlock/SKILL.md`
- Key commands: `varlock load` (validate + show masked values), `varlock run -- <cmd>` (inject secrets into subprocess)
- Secret variable names: TBD — to be defined once secrets are known (see `questions.md`)

## Repository Structure

```
.
├── flake.nix              # Nix flake — pins Python 3.13, uv, alejandra, all dev tools + git hooks
├── pyproject.toml         # Python project metadata and tool configuration
├── dev                    # Executable wrapper: runs `nix develop --command $SHELL`
├── compose.yml            # Podman Compose — agent + OneCLI containers
├── CLAUDE.md              # This file
├── src/lagun/             # src layout — package root
│   └── __init__.py
└── tests/
    └── test_placeholder.py
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

Claude Code is packaged using the per-platform musl npm packages (e.g. `@anthropic-ai/claude-code-linux-x64-musl`). The glibc binary expects a dynamic linker at `/lib64/ld-linux-x86-64.so.2`, which doesn't exist in a pure NixOS container image. The musl variant is statically linked with no such dependency, so it works anywhere without patching.

To update the pinned version:
1. Find the new version on [npmjs.com](https://www.npmjs.com/package/@anthropic-ai/claude-code)
2. Compute the SHA256 SRI hash for each platform's musl tarball:
   ```sh
   nix-prefetch-url --type sha256 \
     https://registry.npmjs.org/@anthropic-ai/claude-code-linux-x64-musl/-/claude-code-linux-x64-musl-VERSION.tgz
   ```
3. Update the `version` string and both platform `hash` values in `flake.nix` under the `claudeCode` derivation

## Key Constraints

- No database
- No CI/CD
- IDE agnostic — no editor-specific config files
- Linux only (`x86_64-linux`, `aarch64-linux`)
- Do not use virtual environments inside the agent container
- Do not use `--no-verify` to skip pre-commit hooks — fix the underlying issue instead
