---
status: completed
---

## Summary

Provide fish shell abbreviations for lagun's CLI commands, automatically loaded when the dev shell is entered.

## Context

lagun exposes three CLI commands to manage the agent container stack (`build-agent-oci-image-into-podman`, `run-agent-stack-in-podman`, `stop-agent-stack-in-podman`), plus two `podman exec` invocations the developer uses constantly to shell in and start Claude Code. Typing these in full is tedious. The user uses fish as their interactive shell and wants short abbreviations available in every project that consumes lagun.

## Requirements

- Lagun defines five abbreviations with `agentContainerName` Nix-interpolated at eval time:
  - `bui` → `build-agent-oci-image-into-podman`
  - `run` → `run-agent-stack-in-podman`
  - `sto` → `stop-agent-stack-in-podman`
  - `she` → `podman exec -it <agentContainerName> bash`
  - `cla` → `podman exec -it <agentContainerName> nix develop --command claude`
- The abbreviations are loaded automatically when `nix develop --command fish` is used — no manual step required.
- The abbreviations are available in both the lagun repo's own shell and in all consuming projects' shells — because `shellHook` runs for both.

## Constraints

- Must not modify `~/.config/fish/config.fish` or any file outside the Nix store and the dev shell environment — user's choice on keeping side-effects minimal and predictable.
- The hook must be idempotent: re-entering the shell must not produce duplicate or conflicting abbreviations — `abbr --add` satisfies this by overwriting any existing abbreviation with the same name.

## Out of scope

- Fish plugin managers (fisher, oh-my-fish, etc.) — vendor conf.d is sufficient.
- Abbreviations for any commands other than the five listed above — user's choice.
- Fish support inside the agent container — out of scope; the agent uses bash.
