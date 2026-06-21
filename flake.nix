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
          agentImageName = "${consumer}-lagun";
          agentContainerName = "${consumer}-lagun-agent";
          onecliContainerName = "${consumer}-lagun-onecli";
          certsVolumeName = "${consumer}-lagun-onecli-certs";
          workdir = "/workspace";
          oneCliUiPort = "10254";
          oneCliPort = "10255";

          ubuntuVersion = "26.04";
          bunVersion = "1.3.14"; # find latest at https://bun.sh/

          dockerfile = pkgs.writeTextFile {
            name = "lagun-Dockerfile";
            text = ''
              FROM docker.io/library/ubuntu:${ubuntuVersion} AS base

              # even using apt-get, some packages ask the user questions
              ENV DEBIAN_FRONTEND=noninteractive

              RUN apt-get update                               \
                && apt-get install -y --no-install-recommends  \
                  git                                          \
                  unzip            `# required to install bun` \
                  curl             `# required to install bun` \
                  ca-certificates  `# required to install bun` \
                && rm -rf /var/lib/apt/lists/*

              RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${bunVersion}"

              ENV PATH="/root/.bun/bin:''${PATH}"
              RUN bun add -g @anthropic-ai/claude-code

              WORKDIR ${workdir}

              CMD ["claude"]
            '';
          };

          composeFile = pkgs.writeTextFile {
            name = "lagun-compose.yml";
            text = ''
              services:
                agent:
                  container_name: ${agentContainerName}
                  image: ${agentImageName}
                  command: sleep infinity
                  environment:
                    HTTP_PROXY: http://onecli:${oneCliPort}
                    HTTPS_PROXY: http://onecli:${oneCliPort}
                    NODE_EXTRA_CA_CERTS: /certs/onecli-ca.crt
                  working_dir: ${workdir}
                  volumes:
                    - .:${workdir}:Z
                    - .agent/config:/root/.config:Z
                    - .agent/claude:/root/.claude:Z
                    - ${certsVolumeName}:/certs:ro
                    - ${workdir}/.agent
                    - .agent/empty-file:${workdir}/.envrc:ro   # keep .envrc out of the agent's reach
                  networks:
                    - onecli

                onecli:
                  container_name: ${onecliContainerName}
                  image: ghcr.io/onecli/onecli:1.36
                  restart: unless-stopped
                  depends_on:
                    postgres:
                      condition: service_healthy
                  ports:
                    - "127.0.0.1:''${ONECLI_APP_PORT:-10254}:10254"
                    - "127.0.0.1:''${ONECLI_GATEWAY_PORT:-${oneCliPort}}:10255"
                  volumes:
                    - app-data:/app/data
                    - ${certsVolumeName}:/certs
                  environment:
                    DATABASE_URL: postgresql://''${POSTGRES_USER:-onecli}:''${POSTGRES_PASSWORD:-onecli}@postgres:5432/''${POSTGRES_DB:-onecli}
                  networks:
                    - onecli

                postgres:
                  image: postgres:18-alpine
                  restart: unless-stopped
                  environment:
                    POSTGRES_USER: ''${POSTGRES_USER:-onecli}
                    POSTGRES_PASSWORD: ''${POSTGRES_PASSWORD:-onecli}
                    POSTGRES_DB: ''${POSTGRES_DB:-onecli}
                  volumes:
                    - pgdata:/var/lib/postgresql
                  ports:
                    - "''${ONECLI_BIND_HOST:-127.0.0.1}:''${POSTGRES_PORT:-5432}:5432"
                  healthcheck:
                    test: ["CMD-SHELL", "pg_isready -U ''${POSTGRES_USER:-onecli}"]
                    interval: 5s
                    timeout: 3s
                    start_period: 15s
                    retries: 10
                  networks:
                    - onecli

              volumes:
                ${certsVolumeName}:
                pgdata:
                app-data:

              networks:
                onecli:
                  driver: bridge
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

                if podman image exists "${agentImageName}"; then
                  echo "image '${agentImageName}' already exists, skipping build" >&2
                  exit 2
                fi

                echo "building '${agentImageName}' image..." >&2
                podman build -f "${dockerfile}" -t ${agentImageName}
                echo "image '${agentImageName}' built successfully" >&2
              '';
            };
          };

          upStack = rec {
            cliName = "run-agent-stack-in-podman";
            cli = pkgs.writeShellApplication {
              name = cliName;
              text = ''
                if ! command -v podman &> /dev/null; then
                  echo "Error: expected podman in PATH, but not found" >&2
                  exit 1
                fi

                if ! podman image exists "${agentImageName}"; then
                  echo "image '${agentImageName}' not found, building it..." >&2
                  podman build -f "${dockerfile}" -t ${agentImageName}
                  echo "image '${agentImageName}' built successfully" >&2
                fi

                echo "creating .agent/ directory" >&2
                mkdir -p .agent/{config,claude}
                touch .agent/empty-file

                echo "rendering compose file to .agent/compose.yml" >&2
                install -m 644 "${composeFile}" .agent/compose.yml

                echo "spinning up stack in the background... (project='${consumer}')" >&2
                podman compose -p ${consumer} -f .agent/compose.yml --project-directory . up -d
                echo "" >&2
                echo "to shell in:         podman exec -it ${agentContainerName} bash" >&2
                echo "to use Claude Code:  podman exec -it ${agentContainerName} claude" >&2
                echo "OneCli dashboard:    http://localhost:${oneCliUiPort}" >&2
                echo "" >&2
              '';
            };
          };

          downStack = rec {
            cliName = "stop-agent-stack-in-podman";
            cli = pkgs.writeShellApplication {
              name = cliName;
              text = ''
                if ! command -v podman &> /dev/null; then
                  echo "Error: expected podman in PATH, but not found" >&2
                  exit 1
                fi

                if [ ! -f .agent/compose.yml ]; then
                  echo "Error: .agent/compose.yml not found, nothing to stop" >&2
                  echo "(did you run ${upStack.cliName} from this directory?)" >&2
                  exit 1
                fi

                echo "tearing down stack... (project='${consumer}')" >&2
                podman compose -p ${consumer} -f .agent/compose.yml --project-directory . down
                echo "stack stopped" >&2
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
              customAgentInPodman.upStack.cli
              customAgentInPodman.downStack.cli
            ];
            shellHook = ''
              ${gitHooks.shellHook}

              ${customAgentInPodman.setGitIgnore.cliBin}

              echo "lagun agent container:" >&2
              echo "" >&2
              echo "  ${customAgentInPodman.buildImage.cliName}" >&2
              echo "  ${customAgentInPodman.upStack.cliName}" >&2
              echo "  ${customAgentInPodman.downStack.cliName}" >&2
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
