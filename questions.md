# Open Questions

Answers needed before implementation can begin.

---

## 1. `varlock` — unknown tool

- What is it, and where does it come from (Nix package, pip, standalone binary, other)?
- How does it work — does it read from a file (`.env`-like), a vault, a specific config format?
- Where does its secrets config live on the host?

## 2. OneCLI configuration

- How is OneCLI configured — YAML/TOML config file, env vars, CLI flags?
- Where does the config live on the host (mounted into the container, or baked in)?
- What does a minimal config look like (even with placeholder secret names)?

## 3. Secret / credential names

- What are the environment variable names that will be injected (even as placeholders, e.g. `MY_API_KEY`)?
- These are needed to wire up both the varlock dummy values and the OneCLI replacement rules.

## 4. Python project structure

- `src/lagun/` layout or flat `lagun/` at project root?
- Any initial modules, entry points, or CLI scripts to stub out?
- Any initial runtime dependencies to declare in `pyproject.toml`?

## 5. Agent container user

- What username should the in-container agent user have (e.g. `agent`, `lagun`, other)?
- With `--userns=keep-id` the container UID maps to the host UID — should the Nix config target a specific UID/GID, or use a generic `1000:1000`?

## 6. Container packages

- Beyond Python 3.13, `uv`, and Claude Code, what other tools must be in the agent container (e.g. `git`, `curl`, `jq`, etc.)?

## 7. Workspace mount point

- Where should the workspace be mounted inside the container — `/workspace`, `/home/agent/workspace`, other?

## 8. Podman Compose file

- Compose filename: `compose.yml` or `docker-compose.yml`?
- Any container resource limits (CPU, memory)?

## 9. CLAUDE.md content

- General agent operating instructions, project-specific guidance, or both?
- Any specific content already in mind, or should reasonable defaults be generated?

## 10. Markdown pre-commit hook

- Most popular `pre-commit` option is `prettier` (requires Node) or `mdformat` (pure Python).
- Given the Python/Nix-only stack, is `mdformat` preferred, or is `prettier` via Nix acceptable?
