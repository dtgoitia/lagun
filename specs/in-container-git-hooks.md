---
status: completed
---

## Summary

Enable Claude Code, running inside its agent container, to use the exact same version of the pre-commit hooks used by a human developer on the host.

## Context

- Claude Code runs inside a container with nix installed.
- Claude Code runs `git commit *` commands inside the container.
- The project's `flake.nix` uses `git-hooks` to manage pre-commit hooks. When a nix dev shell is entered, `git-hooks` runs a setup phase that creates `.pre-commit-config.yaml` as a symlink into the nix store.
- The container mounts `/workspace` from the host, so the `.pre-commit-config.yaml` symlink created by the host's nix shell is already present inside the container.
- When a nix dev shell is entered inside the container, `git-hooks` would normally attempt to recreate that symlink — but it cannot because the file is mounted from the host (resource busy).
- Nix builds are deterministic: the hook resources built inside the container resolve to the same nix store paths as on the host, so the host's symlink works unmodified inside the container.

## Requirements

- When Claude Code (inside its container) runs `git commit *` commands, pre-commit hooks should trigger.
- The pre-commit hooks inside the container must have the exact same result as the ones executed by the human developer outside the container.

## Constraints

- The nix installed inside the agent container cannot manipulate the `.pre-commit-config.yaml` symlink created by `git-hooks` on the host — attempting to do so produces a "resource busy" error.

## Out of scope
