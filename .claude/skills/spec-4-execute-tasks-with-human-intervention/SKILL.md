---
name: spec-4-execute-tasks-with-human-intervention
description: the user mentions a spec by name and wants to work on the tasks in the spec with human supervision
allowed-tools: Read
---

Read project context from [BIG_PICTURE.md](../BIG_PICTURE.md)

The user will name the spec they want to work on.

1. Read the spec file
2. If the `status` in the front matter is `draft`, **STOP** and tell the user 'the spec it not ready to work on yet, because `status: draft`'. Skip all steps below.
3. If the `status` in the front matter is `understood`, **STOP** and tell the user 'the spec it not ready to be tasked-up yet, because `status: understood`'. Skip all steps below.
4. If the `status` in the front matter is `implementation-designed`, **STOP** and tell the user 'the spec it not ready to work on yet, because `status: implementation-designed`'. Skip all steps below.
5. If the `## Tasks` section is missing, **STOP** and tell the user 'the spec it not ready to work on yet, because there are no tasks'. Skip all steps below.
6. In the `## Tasks` section, look for the next unchecked task:
   - if all tasks are completed --> continue to step 11.
   - else, continue to the next step (step 7).
7. Read pending task and implement it.
8. Mark the task checkbox.
9. Commit changes using a git commit message with the task ID at the end of the message. Use this format` [<task-id>]`.
10. **STOP** and **WAIT** for the user instructions to continuing with the next pending task.
11. Once all tasks are completed, let the user know and ask if it wants to finalize the spec file. If the user wants to, then trigger [this skill](../spec-5-finalize/SKILL.md); else end skill.
