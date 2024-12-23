{
  description = "NixOS configuration of our builders";

  nixConfig.extra-substituters = [ "https://nix-community.cachix.org" ];
  nixConfig.extra-trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];

  inputs = {
    buildbot-nix.inputs.flake-parts.follows = "flake-parts";
    buildbot-nix.inputs.hercules-ci-effects.follows = "hercules-ci-effects";
    buildbot-nix.inputs.nixpkgs.follows = "nixpkgs";
    buildbot-nix.inputs.treefmt-nix.follows = "treefmt-nix";
    buildbot-nix.url = "github:nix-community/buildbot-nix";
    cgroup-exporter.inputs.nixpkgs.follows = "nixpkgs";
    cgroup-exporter.url = "github:arianvp/cgroup-exporter";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    empty.url = "github:nix-systems/empty";
    flake-compat.url = "github:nix-community/flake-compat";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    hercules-ci-effects.inputs.flake-parts.follows = "flake-parts";
    hercules-ci-effects.inputs.nixpkgs.follows = "nixpkgs";
    hercules-ci-effects.url = "github:hercules-ci/hercules-ci-effects";
    hydra.flake = false;
    hydra.url = "github:qowoz/hydra/community";
    lite-config.url = "github:yelite/lite-config";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
    nixpkgs-update-github-releases.flake = false;
    nixpkgs-update-github-releases.url = "github:nix-community/nixpkgs-update-github-releases";
    nixpkgs-update.inputs.mmdoc.follows = "empty";
    nixpkgs-update.inputs.treefmt-nix.follows = "treefmt-nix";
    nixpkgs-update.url = "github:nix-community/nixpkgs-update/infra";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    nur-update.inputs.nixpkgs.follows = "nixpkgs";
    nur-update.url = "github:nix-community/nur-update";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    srvos.inputs.nixpkgs.follows = "nixpkgs";
    srvos.url = "github:nix-community/srvos";
    systems.url = "github:nix-systems/default";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    inputs@{ flake-parts, self, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = [
        ./modules
        inputs.lite-config.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      lite-config =
        { lib, ... }:
        {
          nixpkgs = {
            config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "terraform" ];
            overlays = [
              (final: prev: (import ./dev/packages.nix { inherit final prev inputs; }))
            ];
          };

          hostModuleDir = ./hosts;

          hosts = {
            build01.system = "x86_64-linux";
            build02.system = "x86_64-linux";
            build03.system = "x86_64-linux";
            build04.system = "aarch64-linux";
            build05.system = "aarch64-linux";
            darwin01.system = "aarch64-darwin";
            darwin02.system = "aarch64-darwin";
            web02.system = "x86_64-linux";
          };

          systemModules = [
            (
              { hostPlatform, ... }:
              {
                imports =
                  lib.optionals hostPlatform.isDarwin [ ./modules/darwin/common ]
                  ++ lib.optionals hostPlatform.isLinux [ ./modules/nixos/common ];
              }
            )
          ];
        };

      perSystem =
        {
          inputs',
          lib,
          pkgs,
          self',
          system,
          ...
        }:
        {
          imports = [
            ./dev/docs.nix
            ./dev/shell.nix
            ./terraform/shell.nix
          ];
          treefmt = {
            flakeCheck = system == "x86_64-linux";
            imports = [ ./dev/treefmt.nix ];
          };

          checks =
            let
              darwinConfigurations = lib.mapAttrs' (
                name: config: lib.nameValuePair "host-${name}" config.config.system.build.toplevel
              ) ((lib.filterAttrs (_: config: config.pkgs.system == system)) self.darwinConfigurations);
              devShells = lib.mapAttrs' (n: lib.nameValuePair "devShell-${n}") self'.devShells;
              nixosConfigurations = lib.mapAttrs' (
                name: config: lib.nameValuePair "host-${name}" config.config.system.build.toplevel
              ) ((lib.filterAttrs (_: config: config.pkgs.system == system)) self.nixosConfigurations);
            in
            darwinConfigurations
            // devShells
            // {
              inherit (self') formatter;
            }
            // nixosConfigurations
            // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
              inherit (self'.packages) docs docs-linkcheck;
              nixpkgs-update-supervisor-test = pkgs.callPackage ./hosts/build02/supervisor_test.nix { };
              nixosTests-buildbot = pkgs.nixosTests.buildbot;
              nixosTests-buildbot-nix-master = inputs'.buildbot-nix.checks.master;
              nixosTests-buildbot-nix-worker = inputs'.buildbot-nix.checks.worker;
              nixosTests-harmonia = pkgs.nixosTests.harmonia;
              nixosTests-hydra = pkgs.nixosTests.hydra.hydra;
            };
        };
    };
}
