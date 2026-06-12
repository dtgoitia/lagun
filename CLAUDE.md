# CLAUDE.md

## What lagun is

`lagun` is a Nix flake that consuming projects add as a `flake.nix` input. It provides:

- **`lib.mkAgentImage`** — builds a Podman-compatible (OCI) agent container image with Claude Code, the `lagun` user, and the varlock credential skill baked in.
- **`packages.claudeCode`** and **`packages.varlock`** — pre-packaged musl binaries, usable directly in a consuming project's dev shell.
- **`compose.yml`** — a ready-to-use Podman Compose file that starts the coding agent alongside OneCLI.

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
        └── /home/lagun/workspace  ← project root mounted from host
```

Entry point:

```sh
AGENT_IMAGE=my-project-agent:latest podman compose up
```

`compose.yml` (provided by lagun) wires the two containers together, sets `HTTP_PROXY`/`HTTPS_PROXY` on the agent, and waits for OneCLI to be healthy before starting the agent.

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
# flake.nix
inputs.lagun.url = "github:wrsmith108/lagun";

# Build the agent image
packages.${system}.agentImage = lagun.lib.mkAgentImage {
  inherit pkgs;
  name = "my-project-agent";
  extraPackages = [ /* project-specific packages */ ];
};

# Use claudeCode or varlock in the dev shell
devShells.${system}.default = pkgs.mkShell {
  packages = [ lagun.packages.${system}.varlock /* … */ ];
};
```

The consuming project is responsible for:

- Its own `shellHook` (or reuse lagun's `compose.yml` directly)
- Building and loading the image: `nix build .#agentImage && podman load < result`
- Deploying and running the image on whatever infrastructure it targets

---

## lib.mkAgentImage

| Argument        | Type    | Default  | Description                            |
| --------------- | ------- | -------- | -------------------------------------- |
| `pkgs`          | attrset | required | `nixpkgs.legacyPackages.${system}`     |
| `name`          | string  | required | Image name (e.g. `"my-project-agent"`) |
| `extraPackages` | list    | `[]`     | Additional Nix packages to include     |
| `extraEnv`      | list    | `[]`     | Additional `"KEY=value"` env strings   |

Always included: `claude`, `coreutils`, `bash`, `/etc/passwd` with the `lagun` user (uid 1000), and the varlock Claude Code skill at `~/.claude/skills/varlock/SKILL.md`. `NODE_EXTRA_CA_CERTS=/certs/onecli-ca.crt` is pre-set; `HTTP_PROXY`/`HTTPS_PROXY` are wired by `compose.yml` at runtime.

---

## compose.yml

`compose.yml` is provided by lagun and works unchanged in any consuming project. The only required variable is `AGENT_IMAGE`:

```sh
AGENT_IMAGE=my-project-agent:latest podman compose up
```

Or set it in a `.env` file at the project root:

```
AGENT_IMAGE=my-project-agent:latest
```

The file defines:

- **`onecli`** — `ghcr.io/onecli/onecli:1.36`, with a health check that waits for its CA cert to be ready
- **`agent`** — the project's image, with `HTTP_PROXY`/`HTTPS_PROXY` pointing at OneCLI, the workspace mounted, and Claude Code auth persisted from the host

---

## varlock and the varlock Claude Code skill

- Source: [dmno-dev/varlock](https://github.com/dmno-dev/varlock) v1.6.1 (musl binary, no npm install)
- Key commands: `varlock load` (validate + show masked values), `varlock run -- <cmd>` (inject secrets into subprocess)
- Claude Code skill: [wrsmith108/varlock-claude-skill](https://github.com/wrsmith108/varlock-claude-skill) — baked into every image built by `lib.mkAgentImage`; teaches the agent never to echo secrets

---

## Developing lagun itself

The dev shell for working on lagun is minimal — only what's needed to edit Nix and Markdown:

```sh
./dev          # runs: nix develop --command $SHELL
```

Tools available: `alejandra` (Nix formatter), `prettier` (Markdown/YAML). Git hooks run both automatically on commit.

---

## Updating Claude Code

Claude Code is packaged from the per-platform musl npm tarballs (statically linked — no dynamic linker dependency, works in any minimal container image).

1. Find the new version at [npmjs.com/@anthropic-ai/claude-code](https://www.npmjs.com/package/@anthropic-ai/claude-code)
2. Compute SRI hashes:
   ```sh
   nix-prefetch-url --type sha256 \
     https://registry.npmjs.org/@anthropic-ai/claude-code-linux-x64-musl/-/claude-code-linux-x64-musl-VERSION.tgz
   ```
3. Update `version` and both `hash` values inside `buildClaudeCode` in `flake.nix`

---

## Repository structure

```
.
├── flake.nix    # outputs: lib.mkAgentImage, packages.claudeCode, packages.varlock
├── flake.lock   # pinned inputs
├── compose.yml  # Podman Compose — agent + OneCLI; set AGENT_IMAGE before running
├── dev          # ./dev → nix develop --command $SHELL
└── CLAUDE.md    # this file
```
