---
status: completed
---

# Spec: run agent containerized

## Summary

`lagun` exposes a single command that spins up all its containers: the agent container and the OneCLI container.

## Requirements

- `podman compose` drives a two-container (`agent` + `onecli`) workflow.
  - **Why**: the agent needs a side container (OneCLI) to proxy outgoing requests and swap dummy secrets for real ones in-flight; a compose stack is the natural unit for co-locating them.
- The per-consumer `compose.yml` is **rendered by Nix** (`pkgs.writeTextFile`, same pattern as the existing `dockerfile`), with consumer-stamped names baked in directly (`container_name`, volume `name`) — not left to directory-derived defaults.
  - **Why**: baking names in at Nix evaluation time prevents collisions when multiple consuming projects run lagun stacks concurrently on the same host.
- `podman compose` is invoked with `-p ${consumer}` to scope the compose project label / default network. The explicit names are the source of truth for collision-avoidance; `-p` is belt-and-suspenders.
  - **Why**: `-p` scopes the compose project label and default network name, isolating each consumer's stack even if container names were ever to collide.
- The rendered compose file is materialized to `.agent/compose.yml` (gitignored/dockerignored project-local dir) so it's visible and debuggable.
  - **Why**: keeping the rendered file on disk lets developers inspect the exact compose configuration that was used without having to re-evaluate the flake.
- Claude Code's config/session state persists via project-local convention: `.agent/claude` → `/root/.claude`. The agent container runs as **root** at **`/workspace`**. Baking in a real unprivileged `lagun` user + home dir is out of scope (deferred to `specs/varlock.md`).
  - **Why**: mounting `.agent/claude` means Claude Code session state (auth, conversation history) survives container restarts without being committed to the repo.
- The image name is baked into the rendered compose file directly.
  - **Why**: avoids any runtime name derivation so the compose file is self-contained and unambiguous.
- `upStack` (`run-agent-stack-in-podman`) auto-builds the agent image if it doesn't exist, then starts the stack. The build command is also available standalone.
  - **Why**: removes the manual "build then run" two-step from the developer workflow; a fresh checkout just needs one command.
- `downStack` (`stop-agent-stack-in-podman`) runs `podman compose down`.
  - **Why**: tears down all containers and the compose-managed network in one step, leaving no orphaned resources.
