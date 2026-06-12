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
  }: let
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
      mkAgentImage = {
        pkgs,
        name,
        extraPackages ? [],
        extraEnv ? [],
      }: let
        claudeCode = buildClaudeCode pkgs;
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
  in
    (flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
      ]
      (system: let
        pkgs = nixpkgs.legacyPackages.${system};

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
      in {
        packages = {
          claudeCode = buildClaudeCode pkgs;
          varlock = buildVarlock pkgs;
        };

        checks.pre-commit-check = gitHooks;

        devShells.default = pkgs.mkShell {
          packages = [pkgs.alejandra pkgs.prettier];
          shellHook = gitHooks.shellHook;
        };
      }))
    // {inherit lib;};
}
