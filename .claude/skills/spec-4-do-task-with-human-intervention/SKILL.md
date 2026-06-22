---
name: spec-4-do-task-with-human-intervention
description: the user mentions a spec by name and wants to work on the tasks in the spec with human supervision
allowed-tools: Read
---

Read project context from [BIG_PICTURE.md](project/specs/BIG_PICTURE.md)

The user will name the spec they want to work on.

1. Read the spec file
2. If the `status` in the front matter is `draft`, **STOP** and tell the user 'the spec it not ready to work on yet, because `status: draft`'. Skip all steps below.
3. If the `status` in the front matter is `understood`, **STOP** and tell the user 'the spec it not ready to be tasked-up yet, because `status: understood`'. Skip all steps below.
4. If the `status` in the front matter is `implementation-designed`, **STOP** and tell the user 'the spec it not ready to work on yet, because `status: implementation-designed`'. Skip all steps below.
5. If the `## Tasks` section is missing, **STOP** and tell the user 'the spec it not ready to work on yet, because there are no tasks'. Skip all steps below.
6. In the `## Tasks` section, find the next unchecked task, read it and implement it.
7. Once completed, mark the task checkbox, give me a git commit message including the task ID, and **STOP** and **WAIT** for the user instructions to continuing with the next pending task.
