# Implementation Roadmap

Tracks every deliverable described in `CLAUDE.md`. Work top-to-bottom; later sections depend on earlier ones.

---

## 1. Research & Decisions

- [x] **Understand varlock** — Node/npm monorepo CLI (package `varlock` v1.6.1). No `flake.nix` in repo. Ships pre-built Linux binaries (glibc + musl variants) in GitHub releases. Packaged via `fetchurl` + `stdenv.mkDerivation`. Uses `varlock load` / `varlock run -- <cmd>` for secret injection.
- [x] **Understand varlock-claude-skill** — pure-text Claude Code skill at `skills/varlock/SKILL.md`. Teaches Claude never to echo secrets. Install by copying to `~/.claude/skills/varlock/SKILL.md`; baked into the agent image at build time. No binary, no npm install needed.
- [x] **Pin Claude Code version** — `@anthropic-ai/claude-code` v2.1.175. Native binary distributed via per-platform npm packages (e.g. `@anthropic-ai/claude-code-linux-x64-musl`). Using musl variant to avoid glibc issues in NixOS images. Hashes recorded in `flake.nix`.
- [x] **Confirm `ty` availability** — `pkgs.ty` (v0.0.46) exists in `nixos-unstable` at `pkgs/by-name/ty/ty`. Available in devShell as `pkgs.ty`.
- [x] **Confirm `prettier` in nixpkgs** — `pkgs.prettier` exists in `nixos-unstable` at `pkgs/by-name/pr/prettier`. Used directly.
- [x] **Confirm `ty` git-hooks-nix support** — no built-in `ty` hook in git-hooks.nix. Declared as custom hook (`language = "system"`, `entry = "ty check"`, `pass_filenames = false`).
- [x] **Decide varlock Nix flake input strategy** — no `flake.nix` in varlock repo. Using `fetchurl` + `stdenv.mkDerivation` with pre-built musl binaries from GitHub releases.

---

## 2. Core Project Skeleton

- [x] **Create `src/lagun/__init__.py`** — empty file; establishes the src-layout package root.
- [x] **Create `dev` executable** — `#!/usr/bin/env sh` + `exec nix develop --command "$SHELL"`; `chmod +x`.
- [x] **Create `pyproject.toml`** — project metadata, hatchling build backend, src layout, ruff/ty/pytest config.

---

## 3. Nix Flake — Dev Shell

- [x] **Scaffold `flake.nix`** — inputs: `nixpkgs` → nixos-unstable, `flake-utils`, `git-hooks` → `github:cachix/git-hooks.nix`; outputs scoped to `["x86_64-linux" "aarch64-linux"]`.
- [x] **Dev shell packages** — `python313`, `uv`, `alejandra`, `prettier`, `ty`, `ruff`, `varlock`. No manual `pre-commit` — git-hooks.nix manages it.
- [x] **`shellHook`** — composes `gitHooks.shellHook` (hook installation) with venv creation, `uv sync`, and `.venv/bin/activate`.
- [ ] **Verify dev shell** — run `nix develop` (or `./dev`) and confirm Python, uv, prettier, and alejandra are on `$PATH` and `.git/hooks/pre-commit` is installed.

---

## 4. Python Tooling Config

- [x] **`ruff` config in `pyproject.toml`** — `line-length = 88`, `target-version = "py313"`, `select = ["E", "F", "I", "UP"]`.
- [x] **`ty` config in `pyproject.toml`** — `environment.python-version = "3.13"`.
- [x] **`pytest` config in `pyproject.toml`** — `testpaths = ["tests"]`; `tests/test_placeholder.py` created.

---

## 5. Git Hooks (git-hooks-nix)

Hooks are declared in `flake.nix` under `git-hooks.lib.${system}.run { ... }`. No `.pre-commit-config.yaml` is needed.

- [x] **Declare all six hooks in `flake.nix`**:

  | Hook | git-hooks-nix key / approach |
  |---|---|
  | File endings | built-in `end-of-file-fixer` |
  | Markdown (`prettier`) | built-in `prettier` with `pkgs.prettier` |
  | Nix (`alejandra`) | built-in `alejandra` with `pkgs.alejandra` |
  | Python lint (`ruff`) | built-in `ruff` with `pkgs.ruff` |
  | Python format (`ruff-format`) | built-in `ruff-format` with `pkgs.ruff` |
  | Python types (`ty`) | custom hook (`language = "system"`, `entry = "ty check"`) |
  | Python tests (`pytest`) | custom hook (`language = "system"`, `entry = "uv run pytest"`) |

- [ ] **Verify hooks** — enter dev shell and run `pre-commit run --all-files`; confirm all hooks pass on the initial skeleton.

---

## 6. Agent Container Image

- [x] **Add `agentImage` package to `flake.nix`** — `pkgs.dockerTools.buildLayeredImage` with `python313`, `uv`, `claudeCode` (musl), `coreutils`, `bash`, `containerEtc`, `containerHome`.
- [x] **Create `lagun` user in image** — `containerEtc` derivation writes `/etc/passwd` and `/etc/group` with `lagun:x:1000:1000`.
- [x] **Package Claude Code via Nix** — `fetchurl` + `mkDerivation` using the musl npm binary packages. x64 and arm64 hashes pinned in `flake.nix`.
- [x] **Package varlock via Nix** — `fetchurl` + `mkDerivation` using musl GitHub release binaries. Exposed as `packages.varlock`.
- [x] **Set container environment defaults** — `HOME=/home/lagun`, `PATH` (via `lib.makeBinPath`), `NODE_EXTRA_CA_CERTS=/certs/onecli-ca.crt` in `config.Env`.
- [x] **varlock-claude-skill baked into image** — `varlockSkill` fetched via `pkgs.fetchurl`; placed at `/home/lagun/.claude/skills/varlock/SKILL.md` via `containerHome` derivation.
- [ ] **Verify image builds** — run `nix build .#agentImage`, load into Podman, confirm `claude` binary runs.

---

## 7. Podman Compose

- [x] **Create `compose.yml`** — `onecli` and `agent` services defined.
- [x] **Define named volume** — `onecli_certs:` at top level.
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
