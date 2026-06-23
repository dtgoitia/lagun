---
name: spec-5-complete-task
description: the user mentions a spec by name and wants to complete the spec
allowed-tools: Read
---

Read project context from [BIG_PICTURE.md](../BIG_PICTURE.md)

The user will name the spec they want to work on.

1. Read the spec file
2. If the `status` in the front matter is `draft`, **STOP** and tell the user 'the spec it not ready to be completed yet, because `status: draft`'. Skip all steps below.
3. If the `status` in the front matter is `to-task-up`, **STOP** and tell the user 'the spec it not ready to be completed yet, because `status: to-task-up`'. Skip all steps below.
4. If the `## Tasks` section has at least one task with the checkbox unchecked, **STOP** and tell the user 'the spec it not ready to be completed yet, because not all tasks are completed'. Skip all steps below.
5. Review all the changes in the current development branch, and update the spec `## Context`, `## Requirements`, `## Constraints` and `## Out of scope` sections **only** if they are not up to date.
6. Delete the `## Tasks` and `## Implementation` sections.
7. in the spec file frontmatter, set `status: completed`
8. Suggest a git commit message that summarizes the whole branch, provide a short message and a body for the commit message.
