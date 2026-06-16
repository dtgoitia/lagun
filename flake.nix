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
                mkdir -p .agent/{config,claude}

                echo "spinning up container in the background... (name='${containerName}')" >&2
                if ! podman container exists "${containerName}" 2>/dev/null; then
                  podman run --detach                   \
                    --name ${containerName}             \
                    -v .:${workdir}:Z                   \
                    -v .agent/config:/root/.config:Z   \
                    -v .agent/claude:/root/.claude:Z   \
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
        packages = {
          inherit agentInPodman;
        };

        pre-commit-check = gitHooks;

        devShells = {
          createShell = shell;
          default = shell "lagun";
        };
      }
    );
}
