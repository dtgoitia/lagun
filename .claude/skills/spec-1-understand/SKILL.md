---
name: spec-1-understand
description: the user mentions a spec by name and wants to distill or further understand requirements/constraints/context for the spec
allowed-tools: Read
---

Read project context from [BIG_PICTURE.md](../../../specs/BIG_PICTURE.md)

The user will name the spec they want to work on.

1. Read the spec file
2. If the `## Context` section is missing, add it
3. If the `## Requirements` section is missing, add it
4. If the `## Constraints` section is missing, add it
5. If the `## Out of scope` section is missing, add it
6. Thoroughly interview the user to get a deep understanding of this spec, including context not covered in the BIG_PICTURE, spec scope, spec requirements, spec constraints, out of scope work (if needed). If the user replies "TBC", "TBD", "leave it for later" or similar, add your question (word by word) and append it to the numbered list under the `## TBD` section of the spec. If the user replied to your question asking for more context, include the user's reply and your reply (both word by word) too, so that we have a full context of what was discussed regarding this point when we resume the conversation.
7. Add what you've learned to the corresponding section. Make sure to include the "why" for each point under `## Requirements`, `## Constraints` and `## Out of scope` - if the user cannot provide a "why", set the reason as "user's choice".
8. If there are any pending items under `## TBD`, bring them to the user's attention and offer the user to resume the exploration of those items. Remove the items from the list once they are fully addressed.
9. ask the user if:
   - the spec is ready --> continue to the next step
   - or we should to continue with the interview and adding details --> rerun this skill from step 6
10. In the spec file frontmatter, set `status: understood`.
11. Commit the spec file with the `docs(spec): understand` commit message.
12. Ask the user if it wants to proceed to design an implementation. If the user wants to, then trigger [this skill](../spec-2-design-implementation/SKILL.md); else end skill.
