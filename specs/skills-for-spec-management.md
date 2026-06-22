---
status: complete
---

## Summary

Lagun provides a set of default Claude Code skills and copies them into consuming project directories when the developer enters the dev shell. Consuming projects can also declare their own skills alongside them.

## Context

Claude Code skills are directories under `.claude/skills/<skill-name>/` each containing a `SKILL.md` file. They are invoked as slash commands inside a Claude Code session.

Lagun currently has a set of `spec-*` skills living in its own `.claude/skills/` directory. These need to become a first-class lagun output: packaged in `/nix/store` and distributed to consuming projects automatically.

The agent container already mounts the project root, so any skills placed under `.claude/skills/` on the host are automatically available inside the container at the same path.

## Requirements

1. Lagun packages its default skills (currently the `spec-*` set; more will be added over time) as a derivation in `/nix/store`.
2. When a developer enters `nix develop`, the lagun default skills are copied from `/nix/store` into the project's `.claude/skills/<skill-name>/` directory on the host.
3. This copy runs on every shell entry and **overwrites** any manual edits to lagun-managed skill directories — consumers must not hand-edit them.
4. If a consumer skill directory has the same name as a lagun default skill, the shell hook overwrites it and prints a warning to stderr.
5. Consumer projects can add their own skills by placing them directly in `.claude/skills/<skill-name>/` — no lagun API involvement needed. Consumer project skills live outside the flake and are managed entirely by the consumer project.
6. Lagun-managed skill files are available inside the agent container at `.claude/skills/` with no extra mount configuration, because the project root is already mounted.

## Constraints

- Skills must originate from `/nix/store` to remain pure and reproducible.
- The copy is performed inside the `shellHook`; no extra tooling is required at runtime.
- Consuming projects must not manually edit lagun-managed skill directories (changes will be overwritten).
- Lagun provides no API for declaring consumer skills; consumers manage their own skill files directly.

## Out of scope

- Defining new default skills beyond the current `spec-*` set.
- Skill versioning or per-project pinning of skill versions.
- Runtime skill discovery or hot-reload inside the agent container.
- Skill composition, inheritance, or partial overrides.
