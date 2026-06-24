# Spec: run agent containerized

Status: complete

## Summary

`lagun` exposes a single command that spins up all its containers: the agent container and the OneCLI container.

## Requirements

- `podman compose` drives a two-container (`agent` + `onecli`) workflow.
- The per-consumer `compose.yml` is **rendered by Nix** (`pkgs.writeTextFile`, same pattern as the existing `dockerfile`), with consumer-stamped names baked in directly (`container_name`, volume `name`) — not left to directory-derived defaults.
- `podman compose` is invoked with `-p ${consumer}` to scope the compose project label / default network. The explicit names are the source of truth for collision-avoidance; `-p` is belt-and-suspenders.
- The rendered compose file is materialized to `.agent/compose.yml` (gitignored/dockerignored project-local dir) so it's visible and debuggable.
- Claude Code's config/session state persists via project-local convention: `.agent/claude` → `/root/.claude`. The agent container runs as **root** at **`/workspace`**. Baking in a real unprivileged `lagun` user + home dir is out of scope (deferred to `specs/varlock.md`).
- The image name is baked into the rendered compose file directly.
- `upStack` (`run-agent-stack-in-podman`) auto-builds the agent image if it doesn't exist, then starts the stack. The build command is also available standalone.
- `downStack` (`stop-agent-stack-in-podman`) runs `podman compose down`.
