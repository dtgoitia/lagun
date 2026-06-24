---
name: spec-0-create
description: the user mentions it wants to create a new spec
allowed-tools: Read, Bash
---

1. Ask the user for a file name
2. Run `.claude/skills/spec-0-create/script/create-spec.sh <file-name-chosen-by-user>`
3. Commit the spec file with the `docs(spec): create spec` commit message.
4. Ask the user if it wants to proceed to explore the spec context/requirements. If the user wants to, then trigger [this skill](../spec-1-understand/SKILL.md)
