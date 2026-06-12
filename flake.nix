{
  description = "lagun — safe agentic Python development template";

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
    flake-utils.lib.eachSystem
    [
      "x86_64-linux"
      "aarch64-linux"
    ]
    (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};

        # Claude Code — musl (statically linked, no glibc dep, works in NixOS images)
        # Version: 2.1.175 — update via: nix run nixpkgs#prefetch-npm-deps
        claudeCode = let
          version = "2.1.175";
          platforms = {
            x86_64-linux = {
              pkg = "claude-code-linux-x64-musl";
              hash = "sha256-BFsgV4TSeN8cvUWrFn0VMF4P6rHsBmle/tYWhE1OjzE=";
            };
            aarch64-linux = {
              pkg = "claude-code-linux-arm64-musl";
              hash = "sha256-eLUycjGSCXEcn9UYC4ZVkodLdZCnATF4PynYvaEnGi0=";
            };
          };
          p = platforms.${system};
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
        varlock = let
          version = "1.6.1";
          platforms = {
            x86_64-linux = {
              arch = "musl-x64";
              hash = "sha256-0qhjw7iSKfzTnEXoBlRn38bBwJdt0bGM/t2JzT9Y6ok=";
            };
            aarch64-linux = {
              arch = "musl-arm64";
              hash = "sha256-TX93ne+CzYEPpno6bRKMSS0glpmA63aZ5S0/V1OYhKw=";
            };
          };
          p = platforms.${system};
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

        # varlock-claude-skill — fetched at build time and baked into the agent image
        varlockSkill = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/wrsmith108/varlock-claude-skill/main/skills/varlock/SKILL.md";
          hash = "sha256-FUgjDGFE6tfQDVOjdCCjnvNHfSD9y/l2BmgVPf5y9fw=";
        };

        # /etc for the agent container: root + lagun user
        containerEtc = pkgs.runCommand "container-etc" {} ''
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
        containerHome =
          pkgs.runCommand "container-home"
          {
            inherit varlockSkill;
          }
          ''
            mkdir -p "$out/home/lagun/.claude/skills/varlock"
            cp "$varlockSkill" "$out/home/lagun/.claude/skills/varlock/SKILL.md"
            mkdir -p "$out/home/lagun/workspace"
          '';

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

            ruff = {
              enable = true;
              package = pkgs.ruff;
            };

            ruff-format = {
              enable = true;
              package = pkgs.ruff;
            };

            # ty is not a built-in git-hooks.nix hook — custom hook via system
            ty = {
              enable = true;
              name = "ty";
              language = "system";
              entry = "ty check";
              types = ["python"];
              pass_filenames = false;
            };

            # pytest runs via uv so the venv is used consistently
            pytest = {
              enable = true;
              name = "pytest";
              language = "system";
              entry = "uv run pytest";
              types = ["python"];
              pass_filenames = false;
            };
          };
        };
      in {
        packages = {
          inherit varlock claudeCode;

          agentImage = pkgs.dockerTools.buildLayeredImage {
            name = "lagun-agent";
            tag = "latest";
            contents = [
              pkgs.python313
              pkgs.uv
              claudeCode
              pkgs.coreutils
              pkgs.bash
              containerEtc
              containerHome
            ];
            config = {
              User = "lagun";
              Env = [
                "HOME=/home/lagun"
                "PATH=${
                  pkgs.lib.makeBinPath [
                    pkgs.python313
                    pkgs.uv
                    claudeCode
                    pkgs.coreutils
                    pkgs.bash
                  ]
                }"
                "NODE_EXTRA_CA_CERTS=/certs/onecli-ca.crt"
              ];
            };
          };
        };

        checks.pre-commit-check = gitHooks;

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.python313
            pkgs.uv
            pkgs.alejandra
            pkgs.prettier
            pkgs.ty
            pkgs.ruff
            varlock
          ];

          shellHook = ''
            ${gitHooks.shellHook}
            if [ ! -d .venv ]; then
              uv venv .venv
            fi
            if [ -z "''${SKIP_UV_SYNC:-}" ]; then
              uv sync
            fi
            source .venv/bin/activate
          '';
        };
      }
    );
}
