# Spec: run agent containerized

Status: planned

## Problem

- `flake.nix` handles a single OCI container. But we need at least 2 (agent container + OneCLI container).
- `lagun` will be used by multiple projects. To avoid conflicts, each project reuse the OCI images, but their containers must have different names.

## Goal

- `lagun` exposes a single command that spins up all its containers (so far the agent container and the OneCLI container)

## Decisions

- Fully replace the imperative single-container `runContainer` workflow with a `podman compose`-driven two-container (`agent` + `onecli`) workflow. No fallback path is kept.
- The per-consumer `compose.yml` is **rendered by Nix** (`pkgs.writeTextFile`, same pattern as the existing `dockerfile`), with consumer-stamped names baked in directly (`container_name`, volume `name`) — not left to directory-derived defaults.
- `podman compose` is still invoked with `-p ${consumer}` in addition to the explicit names above, purely to scope the compose project label / default network safely. The explicit names remain the source of truth for collision-avoidance; `-p` is belt-and-suspenders.
- The rendered compose file is materialized to `.agent/compose.yml` (already-gitignored/dockerignored project-local dir) so it's visible/debuggable, instead of staying a Nix-store-only artifact.
- Claude Code's own config/session state continues to persist via the existing project-local convention: `.agent/config` → `/root/.config`, `.agent/claude` → `/root/.claude`. The agent container keeps running as **root** at **`/workspace`**, matching the current (simple) Dockerfile — `compose.yml`'s mount paths get fixed to match that, not the other way around. Baking in a real unprivileged `lagun` user + home dir stays out of scope here (deferred to `specs/varlock.md`).
- The new "up" command auto-builds the agent image first if it doesn't exist yet (no separate manual build step required, though the build command stays available standalone too).
- A paired "down" command is added (`podman compose down`), not just "up".
- `AGENT_IMAGE` env var is dropped. The rendered compose file bakes the consumer's image name in directly — one less moving part.
- The static root-level `compose.yml` is removed; it's superseded by the per-consumer Nix-rendered version (whose template lives in `flake.nix`).
- `CLAUDE.md`'s agent-mode "Entry point" snippet gets updated to reflect the new single command instead of `AGENT_IMAGE=... podman compose up`.

## Tasks

- [ ] Remove the root-level static `compose.yml` (superseded by the Nix-rendered, per-consumer version).
- [ ] In `flake.nix`, extend `agentInPodman consumer` with consumer-stamped names reusing the `${consumer}-lagun` convention: `agentContainerName`, `onecliContainerName`, `certsVolumeName`.
- [ ] Add a Nix-rendered `composeFile` (two services: `onecli` + `agent`) with:
  - [ ] explicit `container_name` / volume `name` per consumer baked in
  - [ ] `agent` mount paths matching the current Dockerfile: root user, `/workspace` (not `/home/lagun/workspace`)
  - [ ] `agent` config/credentials mounted from project-local `.agent/{config,claude}` (not `~/.config/claude-code`)
  - [ ] no `AGENT_IMAGE` env var — image name baked in directly
  - [ ] keep the anonymous-volume mask for `${workdir}/.agent` (so the container can't see the host's `.agent/` contents through the project bind-mount)
- [ ] Replace `runContainer` with `upStack` (cli: `run-agent-stack-in-podman`): builds the image first if missing, materializes the rendered compose file to `.agent/compose.yml`, then runs `podman compose -p ${consumer} -f .agent/compose.yml up -d`.
- [ ] Add `downStack` (cli: `stop-agent-stack-in-podman`): runs `podman compose -p ${consumer} -f .agent/compose.yml down`.
- [ ] Update the `shell` devShell (packages list + shellHook banner): drop `runContainer.cli`, add `upStack.cli` + `downStack.cli`.
- [ ] Update `CLAUDE.md`'s agent-mode section/entry point to reflect the new single command instead of manual `AGENT_IMAGE=... podman compose up`.
- [ ] Verify end-to-end with podman: build image, run `upStack`, confirm both containers come up and `onecli` reports healthy before `agent` starts, confirm the agent container can reach OneCLI through the proxy env vars, run `downStack`, confirm clean teardown.
- [ ] Verify two different consumer names can run their stacks simultaneously on the same host without container/volume/network name collisions.
