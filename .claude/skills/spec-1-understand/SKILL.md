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
6. Thoroughly interview the user to get a deep understanding of this spec, including context not covered in the BIG_PICTURE, spec scope, spec requirements, spec constraints, out of scope work (if needed).
7. ask the user if:
   - the spec is ready --> continue to the next step
   - or we should to continue with the interview and adding details --> rerun this skill from step 6
8. In the spec file frontmatter, set `status: understood`.
9. Commit the spec file with the `docs(spec): understand` commit message.
10. Ask the user if it wants to proceed to design an implementation. If the user wants to, then trigger [this skill](../spec-2-design-implementation/SKILL.md); else end skill.
