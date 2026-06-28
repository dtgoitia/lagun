---
status: completed
---

## Summary

Expose the OneCLI CA certificate inside the agent container so that tools (curl, Node.js, etc.) can trust OneCLI's TLS interception.

## Context

OneCLI runs as a side container and acts as an HTTP proxy: it intercepts every outgoing HTTP request from the agent container and swaps dummy secrets for real ones in-flight. Because OneCLI performs TLS interception, its CA certificate must be trusted by the agent container (and other tools) — otherwise TLS-verifying tools will reject connections.

Ubuntu provides a mechanism (`update-ca-certificates` command) to add custom CA certificates to Ubuntu's OS trust store.

Many tools bring their own CA certificate bundle and ignore the system-level CA certificates. Usually these tools honor environment variables (`SSL_CERT_FILE`, `NODE_EXTRA_CA_CERTS`, `NIX_SSL_CERT_FILE`, etc. depending on the tool) and include certificates into their CA certificate bundle.

## Requirements

1. On agent container start, if `/certs/onecli-ca.crt` does not exist, fetch the CA certificate from the OneCLI API and write it to `/certs/onecli-ca.crt`.
   - **Why**: the cert is not written automatically; without it, TLS verification fails for all proxied requests.
2. The cert is fetched from `GET http://onecli:<port>/api/container-config` (no `Authorization` header needed — self-hosted OneCLI).
   - **Why**: this is the OneCLI-provided endpoint for container configuration.
3. The response is JSON; extract the value of the `caCertificate` key and write it to `/certs/onecli-ca.crt`.
   - **Why**: the cert is not returned as raw PEM but embedded (as PEM) in a JSON payload.
4. The fetch must be implemented as a custom bash entrypoint script baked into the agent image.
   - **Why**: `podman-compose` does not support the `post_start` lifecycle hook; an entrypoint wrapper is fully portable and keeps the logic tied to the agent image.
5. The fetch is skipped if `/certs/onecli-ca.crt` already exists (idempotent).
   - **Why**: avoids redundant API calls on container restarts when the cert is already present.
6. The certs volume mount on the agent container must be changed from read-only (`:ro`) to read-write.
   - **Why**: the entrypoint script runs inside the agent container and must write the cert to the shared volume.
7. Once fetched, the cert must also be installed into Ubuntu's OS trust store (`update-ca-certificates`), and `SSL_CERT_FILE`, `NODE_EXTRA_CA_CERTS`, and `NIX_SSL_CERT_FILE` must point at the resulting merged CA bundle rather than the raw cert file.
   - **Why**: pointing those env vars at the raw cert file is not enough — tools like Nix (fetching flake inputs over HTTPS) and `podman` consult the OS trust store, not `SSL_CERT_FILE`/`NODE_EXTRA_CA_CERTS`, so they still reject OneCLI's TLS interception unless the cert is trusted at the OS level.
8. The trust-store installation is skipped if the cert is already present in Ubuntu's custom CA directory (idempotent).
   - **Why**: avoids redundant `update-ca-certificates` runs on container restarts.

## Constraints

- The OneCLI app API is available at port `10254` inside the compose network (hostname `onecli`).
  - **Why**: this is the port OneCLI exposes for its management API, distinct from the gateway/proxy port `10255`.

## Out of scope

- Automatic cert rotation / re-fetching after the cert has been written.
