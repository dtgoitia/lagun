# CLAUDE.md

## What lagun is

`lagun` is a Nix flake that consuming projects add as a `flake.nix` input. It provides:

- **`devShells.createShell { name, extraDockerfileLines? }`** — the main entry point. Returns a dev shell with tooling (alejandra, prettier) and three CLI commands: `build-agent-oci-image-into-podman`, `run-agent-stack-in-podman`, `stop-agent-stack-in-podman`. Internally generates a per-consumer Ubuntu-based Dockerfile (installs Claude Code via bun) and a Podman Compose file with consumer-stamped container and volume names.

There is no Python, no application code, and no copy-paste template here. Lagun is a development dependency.

---

## Two modes of operation

Every project built on lagun supports two modes. The key difference is **who runs** and **how credentials are injected**.

### Human mode (dev shell)

A human developer works directly on the host inside a Nix-managed shell. Real secrets are injected by `varlock` into subprocesses on demand — they are never stored in environment variables or config files in plaintext.

```
host shell
  └── nix develop  (or ./dev)
        ├── tools on $PATH: alejandra, prettier, varlock, …, plus project-specific tools
        └── varlock run -- <cmd>   ← real secrets injected into <cmd> only
```

Entry point:

```sh
./dev          # runs: nix develop --command $SHELL
```

The shell hook installs git hooks and runs any project-specific setup (e.g. `uv sync`).

### Agent mode (container)

A coding agent (Claude Code) runs isolated inside a Podman container. The container holds only **dummy/fake** secrets. OneCLI runs as a side container and acts as an HTTP proxy — it intercepts every outgoing HTTP request and swaps the dummy secrets for real ones in-flight. The real secrets never enter the agent container.

```
host
  ├── OneCLI container  (HTTP proxy, holds real secrets, swaps them in-flight)
  │     └── port 8080
  └── agent container   (Claude Code, dummy secrets, HTTP_PROXY → OneCLI)
        └── /workspace  ← project root mounted from host
```

Entry point:

```sh
run-agent-stack-in-podman   # builds the image if needed, then starts both containers
```

The compose file is rendered by Nix (consumer-stamped container/volume names baked in) and materialized to `.agent/compose.yml`. It wires the two containers together, sets `HTTP_PROXY`/`HTTPS_PROXY` on the agent, and waits for OneCLI to be healthy before starting the agent. Tear the stack down with `stop-agent-stack-in-podman`.

---

## Credentials in each mode

|                       | Human mode                 | Agent mode                         |
| --------------------- | -------------------------- | ---------------------------------- |
| Who runs              | Developer on host          | Claude Code in container           |
| Real secrets location | Host, managed by `varlock` | OneCLI side container              |
| Injection mechanism   | `varlock run -- <cmd>`     | OneCLI HTTP proxy (in-flight swap) |
| Secrets in container  | n/a                        | Dummy values only                  |
| Secrets on disk       | Never in plaintext         | Never                              |

---

## Using lagun in a consuming project

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    lagun = {
      url = "github:dtgoitia/lagun?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    lagun,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        lagunShell = lagun.devShells.${system}.createShell {
          name = "consumer-project";
        };
      in {

        devShells.default = pkgs.mkShell {
          inputsFrom = [ lagunShell ];

          packages = [
            # add more packages
          ];
        };
      }
    );
}
```

The consuming project is responsible for its own `shellHook`.

### Adding packages to the agent image

Pass `extraDockerfileLines` to install extra tooling into the agent container. The lines are placed in a new `FROM base AS consumer` stage so the lagun base stage is never modified.

```nix
lagunShell = lagun.devShells.${system}.createShell {
  name = "consumer-project";
  extraDockerfileLines = ''
    RUN apt-get update && apt-get install -y python3 && rm -rf /var/lib/apt/lists/*
  '';
};
```
