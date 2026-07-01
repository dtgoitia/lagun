---
status: completed
---

## Summary

The agent container authenticates to OneCLI's HTTP proxy every time an agent command runs, so real secrets are swapped in-flight instead of leaking through as dummy values.

## Context

In agent mode, the agent container only holds dummy secrets (e.g. `ANTHROPIC_API_KEY=sk-ant-onecli-placeholder`). OneCLI runs as a side container acting as an HTTP proxy that intercepts outgoing requests and swaps dummy secrets for real ones in-flight.

OneCLI identifies which agent is calling via Basic-auth-style credentials embedded in the proxy URL (`http://x:<agent-access-token>@onecli:<port>`). Without that token on the connection, OneCLI can't identify the caller, so it tunnels the request straight through without TLS-intercepting it — no interception means no header swap, so a dummy secret would leak through untouched and be rejected by the real API.

The agent container's `entrypointScript` fetches `http://onecli:10254/api/container-config`, extracts `.env.HTTP_PROXY` (which contains the correctly-credentialed proxy URL, with `host.docker.internal` swapped for the `onecli` service name since the former isn't resolvable inside the compose network), and exports it as `HTTP_PROXY`/`HTTPS_PROXY` before `exec "$@"`.

The compose file starts the agent container with `command: sleep infinity` — a keep-alive placeholder, not the actual agent workload. Real work happens via `podman exec`: `claudeCmd` and `debugShellCmd` both re-invoke `entrypointScript` as part of the `exec` (`podman exec -it <container> <entrypointScript> nix develop --command claude` / `... bash`). So the token fetch/export isn't a one-time thing that happens when the container is created — it re-runs, fresh, every time a human runs `claude` or opens a debug shell in the running container, in addition to running once against the `sleep infinity` placeholder at container start.

## Requirements

- The agent container must obtain a correctly-credentialed OneCLI proxy URL (`http://x:<agent-access-token>@onecli:<port>`) automatically every time an entrypoint-wrapped command runs — at container start (`ENTRYPOINT`) and at each `podman exec` invocation of Claude Code or a debug shell (`claudeCmd`/`debugShellCmd`) — with no manual step.
  - Why: without the embedded token, OneCLI can't identify the caller and won't intercept/swap secrets, silently leaking dummy values through instead of erroring loudly. Fetching on every invocation (not just container creation) also means a stale/rotated token self-heals on the next `claude` or debug-shell exec, without needing to recreate the container.
- The entrypoint script must retry fetching `http://onecli:10254/api/container-config` until it succeeds.
  - Why: OneCLI may not be healthy yet when the agent container starts, so the entrypoint must be resilient to startup ordering.

## Constraints

## Out of scope

- CA certificate fetch and trust-store setup — same entrypoint script and API call, but tracked separately in `specs/onecli-ca-certificate.md`.
