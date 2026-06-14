{
  description = "lagun - reusable framework for safe agentic development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    git-hooks,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};

        agentInPodman = consumer: rec {
          imageName = "${consumer}-lagun";
          containerName = "${consumer}-lagun";
          workdir = "/workspace";

          dockerfile = pkgs.writeTextFile {
            name = "lagun-Dockerfile";
            text = ''
              FROM docker.io/library/node:20-slim

              RUN apt-get update && apt-get install -y \
                  git \
                  curl \
                  make \
                  && rm -rf /var/lib/apt/lists/*

              RUN npm install -g @anthropic-ai/claude-code

              WORKDIR ${workdir}

              CMD ["claude"]
            '';
          };

          buildImage = rec {
            cliName = "build-agent-oci-image-into-podman";
            cli = pkgs.writeShellApplication {
              name = cliName;
              text = ''
                if ! command -v podman &> /dev/null; then
                  echo "Error: expected podman in PATH, but not found" >&2
                  exit 1
                fi

                if podman image exists "${imageName}"; then
                  echo "image '${imageName}' already exists, skipping build" >&2
                  exit 2
                fi

                echo "building '${imageName}' image..." >&2
                podman build -f "${dockerfile}" -t ${imageName}
                echo "image '${imageName}' built successfully" >&2
              '';
            };
          };

          runContainer = rec {
            cliName = "run-agent-in-podman";
            cli = pkgs.writeShellApplication {
              name = cliName;
              text = ''
                if ! command -v podman &> /dev/null; then
                  echo "Error: expected podman in PATH, but not found" >&2
                  exit 1
                fi

                if ! podman image exists "${imageName}"; then
                  echo "image '${imageName}' not found in podman" >&2
                  echo "to build image, run" >&2
                  echo "" >&2
                  echo "  ${buildImage.cliName}" >&2
                  echo "" >&2
                  exit 1
                fi

                echo "creating .agent/ directory" >&2
                mkdir -p .agent/{.config,.claude}

                echo "spinning up container in the background... (name='${containerName}')" >&2
                if ! podman container exists "${containerName}" 2>/dev/null; then
                  podman run --detach                   \
                    --name ${containerName}             \
                    -v .:${workdir}:Z                   \
                    -v .agent/.config:/root/.config:Z   \
                    -v .agent/.claude:/root/.claude:Z   \
                    -v ${workdir}/.agent                \
                    -w ${workdir}                       \
                    ${imageName} sleep infinity
                  echo "container successfully started in the background" >&2
                elif [ "running" = "$(podman container inspect -f '{{.State.Status}}' "${containerName}" 2>/dev/null)" ]; then
                  echo "container already running" >&2
                else
                  echo "container already existed but was stopped" >&2
                  podman start ${containerName} 2>/dev/null 1>/dev/null
                  echo "container restarted" >&2
                fi
                echo "" >&2
                echo "to shell in:         podman exec -it ${containerName} bash" >&2
                echo "to use Claude Code:  podman exec -it ${containerName} claude" >&2
                echo "" >&2
              '';
            };
          };

          setGitIgnore = rec {
            cliName = "set-gitignore";
            cliBin = "${cli}/bin/${cliName}";
            cli = pkgs.writeShellApplication {
              name = cliName;
              text = ''
                GITIGNORE=".gitignore"
                AGENT_DIR=".agent/"

                if [ ! -f "$GITIGNORE" ]; then
                  echo "$AGENT_DIR" >> "$GITIGNORE"
                  echo ".agent/ added to $GITIGNORE"
                fi

                if ! grep -qxF "$AGENT_DIR" "$GITIGNORE"; then
                  echo "$AGENT_DIR" >> "$GITIGNORE"
                  echo ".agent/ added to $GITIGNORE"
                fi
              '';
            };
          };
        };

        buildClaudeCodeFromNpm = {}; # TODO

        # ── Internal builders (take pkgs, return derivations) ──────────────────
        # Claude Code — musl (statically linked, no glibc dep, works in NixOS images)
        # Version: 2.1.175 — update via CLAUDE.md "Updating Claude Code" instructions
        buildClaudeCode = pkgs: let
          version = "2.1.175";
          p =
            {
              x86_64-linux = {
                pkg = "claude-code-linux-x64-musl";
                hash = "sha256-BFsgV4TSeN8cvUWrFn0VMF4P6rHsBmle/tYWhE1OjzE=";
              };
              aarch64-linux = {
                pkg = "claude-code-linux-arm64-musl";
                hash = "sha256-eLUycjGSCXEcn9UYC4ZVkodLdZCnATF4PynYvaEnGi0=";
              };
            }
        .${
              pkgs.stdenv.hostPlatform.system
            };
        in
          pkgs.stdenv.mkDerivation {
            pname = "claude-code";
            inherit version;
            src = pkgs.fetchurl {
              url = "https://registry.npmjs.org/@anthropic-ai/${p.pkg}/-/${p.pkg}-${version}.tgz";
              hash = p.hash;
            };
            dontUnpack = true;
            dontBuild = true;
            installPhase = ''
              tar -xzf "$src"
              install -Dm755 package/claude "$out/bin/claude"
            '';
          };

        # varlock — musl (statically linked, works on all Linux and in NixOS images)
        # Version: 1.6.1 — https://github.com/dmno-dev/varlock/releases
        buildVarlock = pkgs: let
          version = "1.6.1";
          p =
            {
              x86_64-linux = {
                arch = "musl-x64";
                hash = "sha256-0qhjw7iSKfzTnEXoBlRn38bBwJdt0bGM/t2JzT9Y6ok=";
              };
              aarch64-linux = {
                arch = "musl-arm64";
                hash = "sha256-TX93ne+CzYEPpno6bRKMSS0glpmA63aZ5S0/V1OYhKw=";
              };
            }
        .${
              pkgs.stdenv.hostPlatform.system
            };
        in
          pkgs.stdenv.mkDerivation {
            pname = "varlock";
            inherit version;
            src = pkgs.fetchurl {
              url = "https://github.com/dmno-dev/varlock/releases/download/varlock%40${version}/varlock-linux-${p.arch}.tar.gz";
              hash = p.hash;
            };
            dontUnpack = true;
            dontBuild = true;
            installPhase = ''
              tar -xzf "$src"
              install -Dm755 varlock "$out/bin/varlock"
              install -Dm755 varlock-local-encrypt "$out/bin/varlock-local-encrypt"
            '';
          };

        # /etc for the agent container: root + lagun user
        buildContainerEtc = pkgs:
          pkgs.runCommand "container-etc" {} ''
            mkdir -p "$out/etc"
            printf '%s\n' \
              'root:x:0:0:root:/root:/bin/sh' \
              'lagun:x:1000:1000::/home/lagun:/bin/sh' \
              > "$out/etc/passwd"
            printf '%s\n' \
              'root:x:0:' \
              'lagun:x:1000:' \
              > "$out/etc/group"
          '';

        # /home/lagun skeleton with varlock skill baked in
        buildContainerHome = pkgs: let
          varlockSkill = pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/wrsmith108/varlock-claude-skill/main/skills/varlock/SKILL.md";
            hash = "sha256-FUgjDGFE6tfQDVOjdCCjnvNHfSD9y/l2BmgVPf5y9fw=";
          };
        in
          pkgs.runCommand "container-home" {inherit varlockSkill;} ''
            mkdir -p "$out/home/lagun/.claude/skills/varlock"
            cp "$varlockSkill" "$out/home/lagun/.claude/skills/varlock/SKILL.md"
            mkdir -p "$out/home/lagun/workspace"
          '';

        # ── Public lib ─────────────────────────────────────────────────────────
        lib = {
          # Build a Podman-compatible (OCI) agent container image.
          #
          # name          — image name (e.g. "car-finder-agent")
          # extraPackages — additional Nix packages to include (e.g. [ pkgs.python313 pkgs.uv ])
          # extraEnv      — additional environment variable strings (e.g. [ "FOO=bar" ])
          #
          # The image always includes: claude, coreutils, bash, the lagun user, and the varlock skill.
          # Proxy and cert env vars for OneCLI are pre-set; add HTTP_PROXY/HTTPS_PROXY via compose.
          mkAgentLeanImage = {
            pkgs,
            name,
            extraPackages ? [],
            extraEnv ? [],
          }: let
            claudeCode = buildClaudeCodeFromNpm pkgs;
            containerEtc = buildContainerEtc pkgs;
            containerHome = buildContainerHome pkgs;
            basePkgs = [claudeCode pkgs.coreutils pkgs.bash];
          in
            pkgs.dockerTools.buildLayeredImage {
              inherit name;
              tag = "latest";
              contents = [containerEtc containerHome] ++ basePkgs ++ extraPackages;
              config = {
                User = "lagun";
                Env =
                  [
                    "HOME=/home/lagun"
                    "NODE_EXTRA_CA_CERTS=/certs/onecli-ca.crt"
                    "PATH=${pkgs.lib.makeBinPath (basePkgs ++ extraPackages)}"
                  ]
                  ++ extraEnv;
              };
            };
        };

        gitHooks = git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            end-of-file-fixer.enable = true;
            prettier = {
              enable = true;
              package = pkgs.prettier;
            };
            alejandra = {
              enable = true;
              package = pkgs.alejandra;
            };
          };
        };

        shell = name: let
          customAgentInPodman = agentInPodman name;
        in
          pkgs.mkShell {
            packages = [
              pkgs.alejandra
              pkgs.prettier

              customAgentInPodman.buildImage.cli
              customAgentInPodman.runContainer.cli
            ];
            shellHook = ''
              ${gitHooks.shellHook}

              ${customAgentInPodman.setGitIgnore.cliBin}

              echo "lagun agent container:" >&2
              echo "" >&2
              echo "  ${customAgentInPodman.buildImage.cliName}" >&2
              echo "  ${customAgentInPodman.runContainer.cliName}" >&2
              echo "" >&2
            '';
          };
      in {
        inherit lib;

        packages = {
          inherit agentInPodman;
          varlock = buildVarlock pkgs;
        };

        pre-commit-check = gitHooks;

        devShells = {
          createShell = shell;
          default = shell "lagun";
        };
      }
    );
}
