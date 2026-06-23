---
name: spec-1-understand
description: the user mentions a spec by name and wants to distill or further understand requirements/constraints/context for the spec
allowed-tools: Read
---

Read project context from [BIG_PICTURE.md](../BIG_PICTURE.md)

The user will name the spec they want to work on.

1. Read the spec file
2. If the `## Context` section is missing, add it
3. If the `## Requirements` section is missing, add it
4. If the `## Constraints` section is missing, add it
5. If the `## Out of scope` section is missing, add it
6. Thoroughly interview the user to get a deep understanding of this spec, including context not covered in the BIG_PICTURE, spec scope, spec requirements, spec constraints, out of scope work (if needed).
7. ask the user if:
   - the spec is ready --> in the spec file frontmatter, set `status: understood`
   - or we should to continue with the interview and adding details --> rerun this skill
