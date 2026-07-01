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
        defaultSkills = ./.claude/skills;

        # if this environment variable is set, it indicates we are inside the
        # agent container
        isRunningInContainerEnvVar = "LAGUN_AGENT";

        agentInPodman = {
          name,
          extraDockerfileLines ? "",
          hostOciDaemons ? {},
        }: rec {
          _hostOciDaemons =
            {
              podmanSocket = null;
              dockerSocket = null;
            }
            // hostOciDaemons;

          agentImageName = "${name}-lagun";
          agentContainerName = "${name}-lagun-agent";
          onecliContainerName = "${name}-lagun-onecli";

          agentContainerEntrypointPath = "/usr/local/bin/entrypoint.sh";
          certsVolumeName = "${name}-lagun-onecli-certs";
          certsMountPath = "/certs";
          onecliCaCertFilename = "onecli-ca.crt";
          onecliCaCertPath = "${certsMountPath}/${onecliCaCertFilename}";
          ubuntuCustomCADir = "/usr/local/share/ca-certificates/"; # Ubuntu's default dir to add custom CAs
          ubuntuCABundlePath = "/etc/ssl/certs/ca-certificates.crt"; # CA bundle = default CAs + custom CAs
          oneCliUiPort = "10254";
          oneCliPort = "10255";

          ubuntuVersion = "26.04";
          bunVersion = "1.3.14"; # find latest at https://bun.sh/
          nixVersion = "2.28.3"; # find latest at https://releases.nixos.org/nix/
          dockerComposeVersion = "5.1.3"; # find latest at https://github.com/docker/compose/releases
          nixVolumeName = "${name}-lagun-nix";

          podmanSocketInContainer = "/run/podman/podman.sock";
          dockerSocketInContainer = "/var/run/docker.sock";

          hasPodman = _hostOciDaemons.podmanSocket != null;
          hasDocker = _hostOciDaemons.dockerSocket != null;

          dockerComposeDockerfileBlock =
            if hasDocker
            then ''
              # install docker compose plugin (pinned binary — amd64 only, see Out of scope)
              RUN curl -fsSL https://github.com/docker/compose/releases/download/v${dockerComposeVersion}/docker-compose-linux-x86_64 \
                -o /usr/local/bin/docker-compose \
                && chmod +x /usr/local/bin/docker-compose \
                && mkdir -p /usr/local/lib/docker/cli-plugins \
                && ln -s /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
            ''
            else "";

          entrypointScript = pkgs.writeTextFile {
            name = "agent-entrypoint.sh";
            executable = true;
            text = ''
              #!/usr/bin/env bash
              set -euo pipefail

              # OneCLI only intercepts and swaps secrets into requests whose
              # proxy connection carries this container's agent access token
              # (as the CONNECT/Proxy-Authorization credentials). Without it,
              # OneCLI can't tell which agent is calling and just tunnels the
              # request through untouched, so dummy secrets leak through
              # unmodified. Fetch it fresh on every start (it is cheap, and
              # this call also hands back the CA certificate below).
              echo "ENTRYPOINT: requesting OneCLI container config..." >&2
              until curl -sf http://onecli:10254/api/container-config -o /tmp/onecli-config.json; do
                sleep 2
              done
              echo "ENTRYPOINT: OneCLI container config fetched" >&2

              # OneCLI reports its own address as host.docker.internal, which
              # is not resolvable from inside this compose network -- swap it
              # for the `onecli` service name, keeping the embedded token.
              onecliProxyUrl="$(jq -r .env.HTTP_PROXY /tmp/onecli-config.json | sed 's#host\.docker\.internal#onecli#')"
              echo "ENTRYPOINT: overriding HTTP_PROXY/HTTPS_PROXY to point to ''${onecliProxyUrl}" >&2
              export HTTP_PROXY="''${onecliProxyUrl}"
              export HTTPS_PROXY="''${onecliProxyUrl}"

              # fetch OneCLI's certificate if not present
              if [ ! -f ${onecliCaCertPath} ]; then
                echo "ENTRYPOINT: OneCLI certificate not found at ${onecliCaCertPath}, saving it..." >&2
                jq -r .caCertificate /tmp/onecli-config.json > ${onecliCaCertPath}
              fi

              if [ ! -f /etc/ssl/certs/${onecliCaCertFilename} ]; then
                echo "ENTRYPOINT: adding OneCLI certificate to Ubuntu's trust store" >&2
                # add OneCLI certificate to Ubuntu's default directory for custom CAs
                cp ${onecliCaCertPath} ${ubuntuCustomCADir}

                # Ask Ubuntu to bundle its default CAs with  ones in ${ubuntuCustomCADir}
                update-ca-certificates
              else
                echo "ENTRYPOINT: OneCLI certificate present in Ubuntu's trust store -- if you suspect is stale, rebuild container image" >&2
              fi

              exec "$@"
            '';
          };

          dockerfile = pkgs.writeTextFile {
            name = "lagun-Dockerfile";
            text = ''
              FROM docker.io/library/ubuntu:${ubuntuVersion} AS base

              # even using apt-get, some packages ask the user questions
              ENV DEBIAN_FRONTEND=noninteractive

              # in-container bind-mount target dir for Podman socket must exist in image
              RUN mkdir -p /run/podman

              RUN apt-get update                                 \
                && apt-get install -y --no-install-recommends    \
                  git                                            \
                  unzip            `# required to install bun`   \
                  curl             `# required to install bun`   \
                  ca-certificates  `# required to install bun`   \
                  xz-utils         `# required to install nix`   \
                  jq                                             \
                  podman                                         ${
                if hasDocker
                then "\\\n    docker.io                                      \\"
                else "\\"
              }
                && rm -rf /var/lib/apt/lists/*

              ${
                if hasDocker
                then "RUN usermod -aG docker root"
                else ""
              }

              # install single-user nix
              ENV PATH="/root/.nix-profile/bin:/nix/var/nix/profiles/default/bin:''${PATH}"
              RUN mkdir -p /root/.config/nix                                                       \
                && echo "experimental-features = nix-command flakes" > /root/.config/nix/nix.conf  \
                && groupadd -g 30000 nixbld                                                        \
                && for i in $(seq 1 32); do                                                        \
                    useradd -u $((30000 + i)) -G nixbld -d /var/empty -s /sbin/nologin nixbld$i;   \
                  done                                                                             \
                && mkdir -m 0755 /nix                                                              \
                && curl -fsSL https://releases.nixos.org/nix/nix-${nixVersion}/install             \
                | sh -s -- --no-daemon --yes

              # install Claude Code using Bun
              ENV PATH="/root/.bun/bin:''${PATH}"
              RUN curl -fsSL https://bun.sh/install     \
                | bash -s "bun-v${bunVersion}"          \
                && bun add -g @anthropic-ai/claude-code

              ${dockerComposeDockerfileBlock}

              ${
                if extraDockerfileLines != ""
                then "\n\nFROM base AS consumer\n${extraDockerfileLines}"
                else ""
              }
              COPY oci/entrypoint.sh ${agentContainerEntrypointPath}
              RUN chmod +x ${agentContainerEntrypointPath}
              ENTRYPOINT ["${agentContainerEntrypointPath}"]
              CMD ["nix", "develop", "--command", "claude"]
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
                  ${
                # keep host supplementary groups (e.g. the host `docker` group)
                # so the container process can reach the bind-mounted Docker
                # socket. In rootless Podman the host `docker` GID is unmapped in
                # the container's user namespace, so it shows up as nobody:nogroup
                # and being in the in-container `docker` group does not help —
                # `keep-groups` retains host group membership at the host level
                # instead. Requires the host user to be in the host `docker` group
                # and the `crun` runtime (the rootless default). Not needed for the
                # Podman socket: the host user owns it and maps to container root.
                if hasDocker
                then "group_add:\n      - keep-groups"
                else ""
              }
                  environment:
                    ${isRunningInContainerEnvVar}: "1"

                    ONECLI_AGENT_NAME: ${name}
                    # HTTP_PROXY/HTTPS_PROXY are set at runtime by the entrypoint
                    # script, which embeds the agent access token OneCLI requires
                    # to identify the caller and perform the in-flight swap.
                    NO_PROXY: cache.nixos.org,github.com,raw.githubusercontent.com,objects.githubusercontent.com
                    SSL_CERT_FILE:       ${ubuntuCABundlePath}  # for curl / OpenSSL-based tools
                    NODE_EXTRA_CA_CERTS: ${ubuntuCABundlePath}  # for Node.js tools
                    NIX_SSL_CERT_FILE:   ${ubuntuCABundlePath}  # for nix
                    ${
                if hasPodman
                then "CONTAINER_HOST: unix://${podmanSocketInContainer}"
                else ""
              }
                    ${
                if hasDocker
                then "DOCKER_HOST: unix://${dockerSocketInContainer}"
                else ""
              }
                  working_dir: ''${HOST_PROJECT_PATH}
                  volumes:
                    - ''${HOST_PROJECT_PATH}:''${HOST_PROJECT_PATH}:Z
                    - ''${HOST_PROJECT_PATH}/.agent/config/git:/root/.config/git:Z
                    - ''${HOST_PROJECT_PATH}/.agent/claude:/root/.claude:Z
                    - ''${HOST_PROJECT_PATH}/.agent
                    - ''${HOST_PROJECT_PATH}/.agent/empty-file:''${HOST_PROJECT_PATH}/.envrc:ro   # keep .envrc out of the agent's reach
                    - ${certsVolumeName}:${certsMountPath}
                    - ${nixVolumeName}:/nix
                    ${
                if hasPodman
                then "- ${_hostOciDaemons.podmanSocket}:${podmanSocketInContainer}"
                else ""
              }
                    ${
                if hasDocker
                then "- ${_hostOciDaemons.dockerSocket}:${dockerSocketInContainer}"
                else ""
              }
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
                ${nixVolumeName}:
                pgdata:
                app-data:

              networks:
                onecli:
                  driver: bridge
            '';
          };

          # purpose: development
          # wrapped by entrypoint to expose dynamically tweaked environment variables and CA certs
          # wrapped in nix shell to expose development tooling to the agent
          claudeCmd = "podman exec -it ${agentContainerName} ${agentContainerEntrypointPath} nix develop --command claude";

          # purpose: debugging
          # wrapped by entrypoint to expose dynamically tweaked environment variables and CA certs
          debugShellCmd = "podman exec -it ${agentContainerName} ${agentContainerEntrypointPath} bash";

          fishAbbreviationsFile = pkgs.writeTextFile {
            name = "lagun-fish-abbreviations.fish";
            text = ''
              abbr --add bui ${buildImage.cliName}
              abbr --add run ${upStack.cliName}
              abbr --add sto ${downStack.cliName}
              abbr --add she ${debugShellCmd}
              abbr --add cla ${claudeCmd}
            '';
          };

          # fish auto-sources `vendor_conf.d/*.fish` from every entry in
          # $XDG_DATA_DIRS at startup. Placing the abbreviations here and pointing
          # $XDG_DATA_DIRS at this store path (see shellHook) makes the single fish
          # that `nix develop --command fish` launches register the abbreviations
          # itself — no nested fish required.
          fishVendorConfDir = pkgs.runCommand "lagun-fish-vendor-conf" {} ''
            mkdir -p "$out/fish/vendor_conf.d"
            cp ${fishAbbreviationsFile} "$out/fish/vendor_conf.d/lagun-abbr.fish"
          '';

          bash = {
            guard = {
              runOnlyInHost = ''
                if [ ! -z "''${${isRunningInContainerEnvVar}:-}" ]; then
                  echo "Error: this command must only run on the host, but ${isRunningInContainerEnvVar} environment variable is set to \"''${${isRunningInContainerEnvVar}}\"" >&2
                  exit 1
                fi
              '';
              podmanMustBeInPath = ''
                if ! command -v podman &> /dev/null; then
                  echo "Error: expected podman in PATH, but not found" >&2
                  exit 2
                fi
              '';
            };

            bootstrapAgentDir = ''
              echo "creating .agent/ directory" >&2
              mkdir -p .agent/{config,claude}
              touch .agent/empty-file
            '';

            renderDockerfile = ''
              echo "rendering Dockerfile file to .agent/Dockerfile" >&2
              install -m 644 "${dockerfile}" .agent/Dockerfile
            '';

            renderEntrypointScript = ''
              echo "rendering entrypoint script to oci/entrypoint.sh" >&2
              mkdir -p oci/
              install -m 755 "${entrypointScript}" oci/entrypoint.sh
            '';

            renderComposeFile = ''
              echo "rendering compose file to .agent/compose.yml" >&2
              install -m 644 "${composeFile}" .agent/compose.yml
            '';
          };

          buildImage = rec {
            cliName = "build-agent-oci-image-into-podman";
            cli = pkgs.writeShellApplication {
              name = cliName;
              text = ''
                ${bash.guard.runOnlyInHost}
                ${bash.guard.podmanMustBeInPath}

                if podman image exists "${agentImageName}"; then
                  echo "image '${agentImageName}' already exists, skipping build" >&2
                  exit 3
                fi

                ${bash.bootstrapAgentDir}
                ${bash.renderDockerfile}
                ${bash.renderEntrypointScript}
                ${bash.renderComposeFile}

                echo "building '${agentImageName}' image..." >&2
                podman build -f "${dockerfile}" -t ${agentImageName} .
                echo "image '${agentImageName}' built successfully" >&2
              '';
            };
          };

          upStack = rec {
            cliName = "run-agent-stack-in-podman";
            cli = pkgs.writeShellApplication {
              name = cliName;
              text = ''
                ${bash.guard.runOnlyInHost}
                ${bash.guard.podmanMustBeInPath}

                if ! podman image exists "${agentImageName}"; then
                  echo "image '${agentImageName}' not found, building it..." >&2
                  ${bash.bootstrapAgentDir}
                  ${bash.renderEntrypointScript}
                  podman build -f "${dockerfile}" -t ${agentImageName} .
                  echo "image '${agentImageName}' built successfully" >&2
                fi

                ${bash.bootstrapAgentDir}
                ${bash.renderDockerfile}
                ${bash.renderEntrypointScript}
                ${bash.renderComposeFile}

                echo "spinning up stack in the background... (project='${name}')" >&2
                HOST_PROJECT_PATH="$(pwd)" \
                  podman compose -p ${name} -f .agent/compose.yml up -d
                echo "" >&2
                echo "to shell in:         ${debugShellCmd}" >&2
                echo "to use Claude Code:  ${claudeCmd}" >&2
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
                ${bash.guard.runOnlyInHost}
                ${bash.guard.podmanMustBeInPath}

                if [ ! -f .agent/compose.yml ]; then
                  echo "Error: .agent/compose.yml not found, nothing to stop" >&2
                  echo "(did you run ${upStack.cliName} from this directory?)" >&2
                  exit 3
                fi

                echo "tearing down stack... (project='${name}')" >&2
                HOST_PROJECT_PATH="$(pwd)" \
                  podman compose -p ${name} -f .agent/compose.yml down
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
                ${bash.guard.runOnlyInHost}

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

        shell = {
          name,
          extraDockerfileLines ? "",
          hostOciDaemons ? {
            podmanSocket = null;
            dockerSocket = null;
          },
        }: let
          customAgentInPodman = agentInPodman {inherit name extraDockerfileLines hostOciDaemons;};

          shellHook = {
            common = ''
              ${customAgentInPodman.bash.bootstrapAgentDir}
              ${customAgentInPodman.bash.renderDockerfile}
              ${customAgentInPodman.bash.renderEntrypointScript}
              ${customAgentInPodman.bash.renderComposeFile}
            '';

            # aka, not in-container
            hostOnly = ''
              # git: use host user-level ignored patterns in container
              if [ -f "$HOME/.config/git/ignore" ]; then
                mkdir -p .agent/config/git

                # dereference possible symlinks
                install -m 644 "$HOME/.config/git/ignore" .agent/config/git/ignore
              fi

              # pre-commit: do not attempt to set up `git-hooks` inside the agent container
              #
              # - Context:
              #   - When entering a nix shell on the host, the `git-hooks` in `flake.nix`
              #     create the `.pre-commit-config.yaml`, which is a symlink.
              #   - When the agent container runs, `.pre-commit-config.yaml` is mounted
              #     info the container.
              #   - `.pre-commit-config.yaml`, both in the host and in the container, is
              #     generated deterministically from the same `flake.nix`. In both cases
              #     the file should be identical, and point to the identical nix
              #     resources.
              #   - When a nix shell is entered in the container, the `git-hooks` inside
              #     the container will try to manipulate the `.pre-commit-config.yaml`
              #     file.
              #   - When a nix shell is entered in the container, the nix derivations
              #     built inside the container will be identical to the ones built in
              #     the host.
              #   - When a nix shell is entered in the container, the `git-hooks`
              #     related nix derivations are also built, even if they are used when
              #     entering the nix shell.
              #
              # - Problem: the nix installed inside the agent container cannot
              #   manipulate the mounted `.pre-commit-config.yaml`, it gets an error
              #   saying that the resource is 'busy'.
              #
              # - Solution: do not allow `git-hooks` to run its setup phase when
              #   entering the nix shell inside the container. This way, `git-hooks` won't
              #   attempt to manipulate `.pre-commit-config.yaml`. Using the hosts
              #   `.pre-commit-config.yaml` symlink is fine because the resources needed
              #   will already been built into the in-container nix store, and the symlink
              #   points to exactly the same path in the nix store as the host does
              #   (because the target nix resources were built deterministically).
              ${gitHooks.shellHook}

              ${customAgentInPodman.setGitIgnore.cliBin}

              echo "lagun agent container:" >&2
              echo "" >&2
              echo "  ${customAgentInPodman.buildImage.cliName}" >&2
              echo "  ${customAgentInPodman.upStack.cliName}" >&2
              echo "  ${customAgentInPodman.downStack.cliName}" >&2
              echo "" >&2

              # Make lagun's fish abbreviations available to the fish that
              # `nix develop --command fish` launches, without spawning a nested
              # fish. fish auto-sources vendor_conf.d/*.fish from each
              # $XDG_DATA_DIRS entry at startup, and env vars exported here are
              # inherited by the --command process.
              if command -v fish &>/dev/null; then
                export XDG_DATA_DIRS="${customAgentInPodman.fishVendorConfDir}:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
              fi
            '';

            lagunConsumerOnly = ''
              mkdir -p .claude/skills
              for skill_dir in ${defaultSkills}/*/; do
                skill_name=$(basename "$skill_dir")
                target=".claude/skills/$skill_name"

                if [ -d "$target" ]; then
                  echo "warning: lagun skill '$skill_name' already exists, overwriting" >&2
                fi

                rm -rf "$target"
                cp -r --no-preserve=mode "$skill_dir" "$target"
              done

              # git: ignore lagun skills
              for skill_dir in ${defaultSkills}/*/; do
                skill_name=$(basename "$skill_dir")
                entry=".claude/skills/$skill_name/"

                if ! grep -qxF "$entry" .gitignore 2>/dev/null; then
                  echo "$entry" >> .gitignore
                fi
              done
            '';

            containerOnly =
              (
                if customAgentInPodman.hasPodman
                then ''
                  if [ ! -S "${customAgentInPodman.podmanSocketInContainer}" ]; then
                    echo "Warning: Podman socket not found at ${customAgentInPodman.podmanSocketInContainer}" >&2
                    echo "Container operations (podman, podman compose) will not work." >&2
                    echo "Ensure the host Podman socket is mounted — was the stack started with run-agent-stack-in-podman?" >&2
                  fi
                ''
                else ""
              )
              + (
                if customAgentInPodman.hasDocker
                then ''
                  if [ ! -S "${customAgentInPodman.dockerSocketInContainer}" ]; then
                    echo "Warning: Docker socket not found at ${customAgentInPodman.dockerSocketInContainer}" >&2
                    echo "Container operations (docker, docker compose) will not work." >&2
                    echo "Ensure the host Docker socket is mounted — was the stack started with run-agent-stack-in-podman?" >&2
                  fi
                ''
                else ""
              );
          };
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
              ${shellHook.common}

              ${
                if name == "lagun"
                then "" # do nothing
                else shellHook.lagunConsumerOnly
              }

              if [ -z "''${${isRunningInContainerEnvVar}:-}" ]; then
                ${shellHook.hostOnly}
              else
                :
                ${shellHook.containerOnly}
              fi
            '';
          };
      in {
        packages = {
          inherit agentInPodman;
        };

        pre-commit-check = gitHooks;

        devShells = {
          createShell = shell;
          default = shell {
            name = "lagun";
            hostOciDaemons = {
              podmanSocket = "/run/user/1000/podman/podman.sock";
              dockerSocket = "/var/run/docker.sock";
            };
          };
        };
      }
    );
}
