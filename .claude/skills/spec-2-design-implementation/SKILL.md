---
name: spec-2-design-implementation
description: the user mentions a spec by name and wants to design an implementation for the spec
allowed-tools: Read
---

Read project context from [BIG_PICTURE.md](project/specs/BIG_PICTURE.md)

The user will name the spec they want to work on.

1. Read the spec file
2. If the `status` in the front matter is `draft`, **STOP** and tell the user 'the spec it not ready to design an implementation yet, because `status: draft`'. Skip all steps below.
3. If the `## Implementation` section is missing, add it
4. Thoroughly interview the user to get a clear understanding of the final implementation of this spec. The aim is to understand the final implementation state, not how to arrive to that point.
5. ask the user if:
   - the implementation design is ready --> in the spec file frontmatter, set `status: implementation-designed`
   - or we should to continue with the interview and adding details --> rerun this skill
