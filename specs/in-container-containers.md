---
status: completed
---

## Summary

Enable Claude Code, running inside its agent container, to spawn and manage containers the same way a human developer does on the host.

## Context

I often set up podman containers for development, mainly to:

- avoid polluting my host with project specific dependencies
- avoid conflicts across different project dependencies
- environment reproducibility

These containers are also used to run tests.

I am using a container to run Claude Code isolated for the same reasons I use development containers.

## Requirements

The agent must be able to run and test code as close as possible to how a human developer does on the host:

- If the human runs tests inside a specific container with a specific configuration, the agent must be able to run the same container with the same configuration.
- The feedback loop must be equivalent: agent and human see the same test output from the same containers.
- The agent must be able to: build images (`podman build`), pull images from public registries, run containers with mounts/ports/env vars (`podman run`), stop and remove containers, and read container logs.
- Multi-container setups (`podman-compose` or `docker compose`) are in scope if the consuming project uses them.
- Socket passthrough is always present in the lagun agent stack (not opt-in), because lagun consumers are expected to use development/test containers most of the time.
- `podman` client must be installed in the lagun base Dockerfile via `apt-get install podman` (Ubuntu 26.04 default repo) so all consumers get it automatically without needing `extraDockerfileLines`. Ubuntu 26.04 (Resolute) ships Podman 5.7.0 — accepted, since the minimum version constraint (5.8.3) applies to the host Podman daemon, not the in-container client. Podman 5.7.0 also includes `podman compose` as a built-in (added in 4.7), so no separate installation is needed for it.
- The host socket path is resolved at `run-agent-stack-in-podman` invocation time via `$XDG_RUNTIME_DIR/podman/podman.sock`.
  - context: when podman runs, it talks to its daemon using a socket, this socket (aka host socket) is user-specific, and must be exposed inside the container
- The agent container must mirror the host directory structure: the project root must be mounted at the same absolute path inside the container as it occupies on the host (e.g. if the project lives at `/home/johndoe/projects/myproject` on the host, it must be mounted at `/home/johndoe/projects/myproject` inside the container, not at `/workspace`). This is required because when `docker compose` runs inside the container it resolves volume paths (e.g. `./src`) to absolute paths based on the compose file location; those absolute paths are then sent to the host Podman daemon, which tries to mount them on the host filesystem. If the in-container path differs from the host path, volume mounts in consumer compose files will point at wrong or non-existent locations.
  - This requires changing the compose `workdir` from the current hardcoded `/workspace` to the host's absolute project path, resolved at `run-agent-stack-in-podman` invocation time. The Nix-generation mechanism stays; only the content of the generated compose changes. There are no existing consuming projects, so no migration path is needed.
- The agent container exposes whichever socket(s) are mounted via its environment: `CONTAINER_HOST` (for `podman` / `podman compose`) when a Podman socket is configured, and `DOCKER_HOST` (for `docker` / `docker compose`, which reads a different variable) when a Docker socket is configured. Podman's socket is Docker-API-compatible, so `DOCKER_HOST` can also point at a Podman socket. Which sockets are mounted is controlled by the `hostOciDaemons` parameter.
- For the **Podman** socket no permission adjustment is needed: the container runs as root (UID 0), and rootless Podman's user namespace maps the host user (who owns the socket) to container root — so root inside the container sees the socket as its own and can access it without extra configuration. The **Docker** socket does not benefit from this mapping and currently fails with `permission denied` under rootless Podman — see [Known limitations](#known-limitations).
- Both `podman compose` (built into the `podman` package) and `docker compose` must be available in the agent container, to cover whichever tool a consuming project uses. `docker compose` is installed by downloading a pinned binary from GitHub releases (same pattern as bun today) — no third-party apt repo needed.
- The agent is responsible for stopping containers it starts, the same way a human would (e.g. `docker compose down`). `stop-agent-stack-in-podman` does not need to track or remove agent-spawned containers. Containers that linger after an unexpected agent teardown are a known limitation.
- Spawned containers do not need to route through OneCLI — consuming projects' dev/test containers are not expected to make authenticated HTTP calls that require credential injection.

## Constraints

- Must stay rootless — the host already runs rootless Podman; requiring root would change the host setup and undermine lagun's isolation model.
- Must not require `--privileged` — `--privileged` grants near-full host access inside the container, defeating the agent isolation that lagun is designed to provide (a prompt injection could escape to the host).
- The Nix-generation mechanism for the compose file must be preserved — consumers must not need to manually edit compose files. The generated compose content may change (e.g. workdir, new volume mounts, new env vars).
- Minimum Podman version: 5.8.3 (rootless) - because it's the one used by the user on the host
- Containers spawned by the agent use the shared default Podman network; dedicated network isolation is not required — user's choice.

## Out of scope

- Private registry support - to simplify implementation.
- CI/CD, host-only for now - to simplify implementation.
- arm64 support for the agent container: the `docker compose` binary is downloaded as `linux-x86_64` (amd64 only). An arm64 host would need a different binary. Known limitation — to be addressed if an arm64 host is needed in the future.
- Rootless Podman-in-Podman: running a full nested Podman daemon inside the agent container using user namespaces. Spawned containers would be true children of the agent container, but requires `--privileged` or complex capability + uid/gid mapping setup.
- Sysbox runtime: a dedicated OCI runtime for safe container-in-container without `--privileged`. Provides the best security posture but requires Sysbox installed on the host, is not available in standard Nix/NixOS packages, and adds a host-level dependency that must be reproduced on the VPS and every collaborator's machine.

## Known limitations

### Docker socket access from inside the agent container fails under rootless Podman (unresolved)

The Podman socket path works fully and is the recommended configuration. The **Docker** socket path is shipped (the `hostOciDaemons.dockerSocket` flake API mounts the socket, sets `DOCKER_HOST`, installs `docker` + `docker compose`, and emits `group_add: ["keep-groups"]`) but is **best-effort and currently does not work** in our rootless setup.

Symptom: when the agent is wired to a host **Docker** socket, running `docker ps` inside the agent container returns

```
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```

even though `root` (the container user) is in the `docker` group and `group_add: ["keep-groups"]` is set.

Root cause — it's a **user-namespace ID-mapping** problem, not a group-membership problem:

- A rootless Podman container runs in a user namespace. The host user (e.g. UID 1000) maps to `root` (UID 0) inside the container; the rest map through the `/etc/subuid` and `/etc/subgid` ranges.
- The host's `/var/run/docker.sock` is owned by `root:docker`, where `docker` is a GID on the **host** (often 999). That GID is almost always **outside** the mapped subgid range, so inside the container the socket appears owned by `nobody:nogroup` (65534).
- Adding `root` to the container's `docker` group assigns it whatever GID that group has inside the container — unrelated to the socket's real owner. The kernel enforces access using the **host-level** identity behind the namespace (host UID 1000), which is neither the socket owner nor — from the namespace's view — in its group → `permission denied`.
- This is why adding the user to the `docker` group in the Dockerfile (commit `f258ba0`) had no effect.

Confirm with (inside the container): `ls -ln /var/run/docker.sock` — numeric owner/group showing `65534` confirms the diagnosis.

Decision: **accepted as a known gap** and the spec is closed with it. The flake API stays the same — `hostOciDaemons.dockerSocket` still wires everything up — so the path can be revisited later without an API change. Candidate fixes, not yet applied/verified end-to-end (rootless, in preference order):

1. `podman run --group-add keep-groups` (compose: `group_add: ["keep-groups"]`). Retains the host's supplementary groups, so the container process keeps host `docker` group membership at the host level and can reach the socket. Requires: the **host** user running Podman is in the host `docker` group, and the OCI runtime is `crun` (default; implements the `run.oci.keep_original_groups` annotation — `runc` does not). This is already emitted in the compose file but, as observed, is not sufficient on its own in our setup (likely because the host user is not in the host `docker` group, or the runtime/annotation prerequisites are not met).
2. Use Podman's own socket instead of Docker's: expose the rootless Podman socket (`podman system service`) and point `DOCKER_HOST`/`CONTAINER_HOST` at it. Avoids the host-Docker-daemon mapping entirely and stays rootless end-to-end. This is the approach the spec already takes for the Podman path — when the agent talks to the **host's rootless Podman** socket, the host user owns the socket and maps to container root, so no fix is needed. The problem above only arises when the socket is the **Docker** daemon's socket.
3. `chmod 666` the socket on the host. Works but insecure — anyone with socket access has effective root over whatever the daemon controls.
