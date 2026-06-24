---
name: spec-2-design-implementation
description: the user mentions a spec by name and wants to design an implementation for the spec
allowed-tools: Read
---

Read project context from [BIG_PICTURE.md](../../../specs/BIG_PICTURE.md)

The user will name the spec they want to work on.

1. Read the spec file
2. If the `status` in the front matter is `draft`, **STOP** and tell the user 'the spec it not ready to design an implementation yet, because `status: draft`'. Skip all steps below.
3. If the `## Implementation` section is missing, add it
4. Thoroughly inspect the spec and thoroughly think of questions to clarify any vagueness. We aim to get a clear understanding of the final implementation of this spec, we don't care how arrive to this final implementation. Add your question (word by word) and append it to the numbered list under the `## TBD` section of the spec, so that we have a full context of what was discussed regarding this point when we revisit this point later in the conversation.
5. If there are any pending items under `## TBD`, bring them to the user's attention and offer the user to resume the exploration of those items.
6. Add what you've learned during the discussion of the `## TBD items` to the `## Implementation` section. Be specific, assume the reader will know nothing when it needs to build tasks out of what you write, so make sure to add details.
7. Ask the user if the item is fully addressed:
   - if fully addressed --> remove the item from the list and move to the next step
   - else --> jump to step 5 again with this item.
8. ask the user if:
   - the implementation design is ready --> continue to the next step
   - or we should to continue with the interview and adding details --> rerun this skill from step 4
9. In the spec file frontmatter, set `status: implementation-designed`.
10. Commit the spec file with the `docs(spec): design implementation` commit message.
11. Ask the user if it wants to proceed to task-up the spec. If the user wants to, then trigger [this skill](../spec-3-task-up/SKILL.md); else end skill.
