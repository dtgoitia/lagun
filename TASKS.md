# Implementation Roadmap

Tracks every deliverable described in `CLAUDE.md`. Work top-to-bottom; later sections depend on earlier ones.

---

## 1. Research & Decisions

- [ ] **Understand varlock** — read `https://github.com/dmno-dev/varlock`: is it a Node/npm CLI, a binary, or something else? Determine how to package it in Nix (e.g. `buildNpmPackage`, `mkDerivation`, fetched binary).
- [ ] **Understand varlock-claude-skill** — read `https://github.com/wrsmith108/varlock-claude-skill`: what does this skill do and does it need to be bundled into the image or installed separately?
- [ ] **Pin Claude Code version** — find the current `@anthropic-ai/claude-code` version on npmjs.com, run `nix run nixpkgs#prefetch-npm-deps` to obtain the hash, record both in `flake.nix`.
- [ ] **Confirm `ty` availability** — check whether `ty` (Astral type checker) is in `nixpkgs-unstable`; if not, plan a fallback (e.g. install via `uv tool` or build from source).
- [ ] **Confirm `prettier` in nixpkgs** — verify `pkgs.nodePackages.prettier` or `pkgs.prettier` exists in nixos-unstable and is usable as a git-hooks-nix hook binary.
- [ ] **Confirm `ty` git-hooks-nix support** — check whether `git-hooks.nix` has a built-in `ty` hook; if not, plan the custom hook declaration (`id`, `entry`, `language = "system"`).
- [ ] **Decide varlock Nix flake input strategy** — if varlock is an npm package, add it as a `flake.nix` input via `github:dmno-dev/varlock` only if the repo contains a `flake.nix`; otherwise write a `buildNpmPackage` derivation inline.

---

## 2. Core Project Skeleton

- [ ] **Create `src/lagun/__init__.py`** — empty file; establishes the src-layout package root.
- [ ] **Create `dev` executable** — one-liner: `#!/usr/bin/env sh` + `exec nix develop --command $SHELL`; `chmod +x`.
- [ ] **Create `pyproject.toml`** — project metadata for `lagun`, src layout (`packages = [{include = "lagun", from = "src"}]`), tool sections for `ruff`, `ty`, and `pytest`.

---

## 3. Nix Flake — Dev Shell

- [ ] **Scaffold `flake.nix`** — declare inputs: `nixpkgs` → nixos-unstable, `flake-utils`, `git-hooks` → `github:cachix/git-hooks.nix`; scope outputs to `["x86_64-linux" "aarch64-linux"]`.
- [ ] **Dev shell packages** — include `python313`, `uv`, `alejandra`, `prettier` (or `nodePackages.prettier`), and any tool needed for the `ty` hook. Do **not** add `pre-commit` manually — git-hooks-nix manages it.
- [ ] **`shellHook`** — compose git-hooks-nix's generated `shellHook` with the project's own three-step sequence:
  1. `${config.pre-commit.installationScript}` (git-hooks-nix auto-installs hooks)
  2. `if [ ! -d .venv ]; then uv venv .venv; fi`
  3. `if [ -z "${SKIP_UV_SYNC:-}" ]; then uv sync; fi`
  4. `source .venv/bin/activate`
- [ ] **Verify dev shell** — run `nix develop` (or `./dev`) and confirm Python, uv, prettier, and alejandra are on `$PATH` and `.git/hooks/pre-commit` is installed.

---

## 4. Python Tooling Config

- [ ] **`ruff` config in `pyproject.toml`** — set `line-length`, `target-version = "py313"`, sensible lint rule selection.
- [ ] **`ty` config in `pyproject.toml`** — point `src` at `src/`, enable strict mode if desired.
- [ ] **`pytest` config in `pyproject.toml`** — set `testpaths = ["tests"]`, add `tests/` directory with a placeholder `test_placeholder.py` that passes.

---

## 5. Git Hooks (git-hooks-nix)

Hooks are declared in `flake.nix` under `git-hooks.lib.${system}.run { ... }`. No `.pre-commit-config.yaml` is needed.

- [ ] **Declare all six hooks in `flake.nix`**:

  | Hook | git-hooks-nix key / approach |
  |---|---|
  | File endings | built-in `end-of-file-fixer` |
  | Markdown (`prettier`) | built-in `prettier` pointing to `pkgs.prettier` |
  | Nix (`alejandra`) | built-in `alejandra` pointing to `pkgs.alejandra` |
  | Python lint/format (`ruff`) | built-in `ruff` pointing to `pkgs.ruff` |
  | Python types (`ty`) | custom hook (`language = "system"`, `entry = "ty check"`) if no built-in |
  | Python tests (`pytest`) | custom hook (`language = "system"`, `entry = "uv run pytest"`) |

- [ ] **Verify hooks** — enter dev shell and run `pre-commit run --all-files`; confirm all six hooks pass on the initial skeleton.

---

## 6. Agent Container Image

- [ ] **Add `agentImage` package to `flake.nix`** — use `pkgs.dockerTools.buildLayeredImage`:
  - `name = "lagun-agent"`, `tag = "latest"`
  - `contents`: `python313`, `uv`, Claude Code (npm package derivation)
  - `config.User = "lagun"`, set `HOME`, `PATH`
- [ ] **Create `lagun` user in image** — add a `passwdEntry` / `groupEntry` or use `pkgs.fakeNss` so the `lagun` user exists inside the container.
- [ ] **Package Claude Code via Nix** — write a `buildNpmPackage` (or `mkDerivation` with `prefetch-npm-deps`) derivation for `@anthropic-ai/claude-code` at the pinned version+hash from step 1.3.
- [ ] **Package varlock via Nix** — write the derivation determined in step 1.1 / 1.6. Expose it as `packages.varlock`.
- [ ] **Set container environment defaults** — bake `NODE_EXTRA_CA_CERTS`, `HOME=/home/lagun`, `PATH` into `config.Env` in the image definition.

---

## 7. Podman Compose

- [ ] **Create `compose.yml`** — define two services:

  **`onecli` service**
  - Image: `ghcr.io/onecli/onecli:1.36`
  - Mount named volume `onecli_certs:/certs` (or wherever OneCLI writes its CA)
  - Add healthcheck so the agent waits for it

  **`agent` service**
  - Image: built from `flake.nix` `agentImage` output (or reference by name/tag)
  - `userns_mode: keep-id`
  - Volumes:
    - `.:/home/lagun/workspace` (workspace)
    - `~/.config/claude-code:/home/lagun/.config/claude-code` (auth persistence)
    - `onecli_certs:/certs:ro` (CA bundle)
  - Environment:
    - `HTTP_PROXY` / `HTTPS_PROXY` → OneCLI proxy address
    - `NODE_EXTRA_CA_CERTS` → path to OneCLI CA cert inside container
  - `depends_on: onecli: condition: service_healthy`

- [ ] **Define named volume** — `volumes: onecli_certs:` at the top level of `compose.yml`.
- [ ] **Verify compose file parses** — run `podman compose config` (or `docker compose config`) and confirm no YAML/schema errors.

---

## 8. varlock Integration

- [ ] **Clarify varlock config format** — once step 1.1 is done, document how varlock reads secrets (file path, format, env var pointing to config). Add to `CLAUDE.md`.
- [ ] **Create dummy secrets config** — add a varlock config file (or template) with placeholder/dummy values for the agent container. File should live at a path that varlock picks up automatically in agent mode.
- [ ] **Wire varlock into dev shell** — add varlock invocation to `shellHook` (before activating `.venv`) so real secrets are injected in developer mode.
- [ ] **Document secret variable names** — once known, fill in `questions.md` Q1 and update the `## varlock` section of `CLAUDE.md`.

---

## 9. Verification & Polish

- [ ] **End-to-end developer mode test** — run `./dev`, confirm shell activates, `python --version` returns 3.13, `uv`/`prettier`/`alejandra` are on PATH, and `.git/hooks/pre-commit` exists.
- [ ] **End-to-end agent mode test** — build image (`nix build .#agentImage`), load it into Podman, run `podman compose up`, confirm agent container starts and OneCLI is reachable.
- [ ] **Pre-commit clean run** — `pre-commit run --all-files` passes with zero violations on the initial skeleton.
- [ ] **Update `CLAUDE.md` repository structure** — reflect any paths added during implementation (e.g. `tests/`, varlock config file, etc.).
- [ ] **Close resolved items in `questions.md`** — once secret names are known, remove that last open question.
