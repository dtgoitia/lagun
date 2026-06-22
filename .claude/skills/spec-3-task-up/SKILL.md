---
name: spec-3-task-up
description: the user mentions a spec by name and wants to plan tasks for the spec
allowed-tools: Read
---

Read project context from [BIG_PICTURE.md](project/specs/BIG_PICTURE.md)

The user will name the spec they want to work on.

1. Read the spec file
2. If the `status` in the front matter is `draft`, **STOP** and tell the user 'the spec it not ready to be tasked-up yet, because `status: draft`'. Skip all steps below.
3. If the `status` in the front matter is `understood`, **STOP** and tell the user 'the spec it not ready to be tasked-up yet, because `status: understood`'. Skip all steps below.
4. If the `## Tasks` section is missing, add it
5. Add the concrete task breakdown as a checklist/section under the `## Tasks` section.
   - Assign an incremental integer as a task identifier to later refer to it in the git commits.
   - This task checkbox-list will be used later to check-items off as they are implemented
6. in the spec file frontmatter, set `status: tasked-up`
