---
name: spec-0-create
description: the user mentions it wants to create a new spec
allowed-tools: Read, Bash
---

1. Ask the user for a file name
2. Run the following script:

```bash
cat << 'EOF' > specs/<file-name-chosen-by-user>.md
---
status: draft
---
## Summary

## Context

## Requirements

## Constraints

## Out of scope

EOF
```

Ask the user if it wants to proceed to fill up the task. If the user wants to, then trigger [this skill](../spec-1-understand/SKILL.md)
