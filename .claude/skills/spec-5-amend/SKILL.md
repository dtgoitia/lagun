---
name: spec-5-amend
description: the user mentions a spec by name and describes a new change they want to add to the spec, then wants the spec updated and the change implemented
allowed-tools: Read
---

Read project context from [BIG_PICTURE.md](../../../specs/BIG_PICTURE.md)

The user will name the spec they want to amend and describe the new change in their message.

1. Read the spec file.
2. If the `status` in the front matter is not `tasked-up`, **STOP** and tell the user the skill only works on specs with `status: tasked-up`. Skip all steps below.
3. If the new change requested by the user is unclear, ask the user until the new change is understood.
4. Update the `## Implementation` section to describe the new change. Add a new numbered sub-section (continuing from the last existing one).
5. Add one or more tasks to the `## Tasks` section for the new change. Assign incremental integer IDs continuing from the last existing task ID.
6. Commit the spec file with the message `docs(spec): amend`.
7. Implement the new task(s) one by one:
   a. Implement the task.
   b. Mark the task checkbox.
   c. Commit with the task ID at the end of the message, using this format: `[<task-id>]`.
   d. If there are more new tasks, repeat from step 6a.
8. Let the user know all new tasks are complete.
