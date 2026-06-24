# lagun

`lagun` is a Nix flake that consuming projects add as a `flake.nix` input. It provides:

- A nix shell with formatting tools and CLI commands to build and use an isolated Claude Code agent container.

## Usage

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    lagun.url = "github:your-org/lagun";
  };

  outputs = { self, nixpkgs, flake-utils, lagun }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      lagunShell = lagun.devShells.${system}.createShell {
        name = "my-project";
      };
    in {
      devShells.default = pkgs.mkShell {
        inputsFrom = [ lagunShell ];
        packages = [ /* project-specific tools */ ];
      };
    });
}
```

### Adding packages to the agent image

Pass `extraDockerfileLines` to install extra tooling into the agent container. The lines are placed in a new `FROM base AS consumer` stage so the lagun base stage is never modified.

```nix
lagunShell = lagun.devShells.${system}.createShell {
  name = "my-project";
  extraDockerfileLines = ''
    RUN apt-get update && apt-get install -y python3 && rm -rf /var/lib/apt/lists/*
  '';
};
```

## Running the agent

```sh
run-agent-stack-in-podman
# then, to enter Claude Code inside the dev shell:
podman exec -it my-project-lagun-agent nix develop --command claude
```

Tear down with `stop-agent-stack-in-podman`.

## Nix store volume

The agent container persists the Nix store across runs via a named Podman volume (`<name>-lagun-nix`). The entire `/nix` directory is mounted — not just `/nix/store` — because Nix also uses `/nix/var` for profiles, gc-roots, and other state. Mounting only `/nix/store` would leave that state ephemeral and break `nix develop` across container restarts.

The first `nix develop` after a fresh volume downloads nixpkgs and builds the dev shell; this takes several minutes. Subsequent runs reuse the cached store and are fast.

### Clearing the Nix store volume

To reclaim disk space or force a clean rebuild:

```sh
podman volume rm <name>-lagun-nix
```

The next `nix develop` will re-download everything from scratch.

## Why Nix traffic bypasses OneCLI (`NO_PROXY`)

The agent container routes all HTTP/HTTPS traffic through OneCLI, an in-flight secret-swapping proxy. OneCLI performs HTTPS inspection (MITM) to swap dummy secrets for real ones — this breaks Nix's TLS verification because the TLS certificate chain no longer matches.

The following domains are excluded via `NO_PROXY`:

- `cache.nixos.org` — the default Nix binary cache
- `github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com` — GitHub endpoints Nix fetches flake inputs from

These are all public endpoints that carry no secrets, so bypassing OneCLI is both necessary (to preserve TLS integrity) and safe (nothing sensitive is in transit).

Note: `NO_PROXY` is OS-wide and affects all tools in the container (curl, wget, etc.), not just Nix.
