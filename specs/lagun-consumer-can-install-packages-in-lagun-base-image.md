---
status: completed
---

# Spec: `lagun` consumer extend `lagun` Dockerfile to can install packages

## Summary

Consumers can pass `extraDockerfileLines` to `createShell` to install stack-specific tools (Python, Rust, JVM, etc.) into the agent container image. The lines are injected into a `FROM base AS consumer` stage in the generated Dockerfile, leaving the lagun `base` stage untouched.

## Requirements

- `createShell` accepts an attrset `{ name, extraDockerfileLines ? "" }` — `extraDockerfileLines` is optional and defaults to no consumer stage
- when `extraDockerfileLines` is provided, the generated Dockerfile appends a `FROM base AS consumer` stage containing those lines
- `CMD ["claude"]` always closes the last open stage, whether or not a consumer stage exists
- the lagun `base` stage is never modified; all consumer additions happen in downstream stages only
