{ config, lib, ... }:

let
  inherit (lib) mkEnableOption mkOption types;
  sizeType = types.strMatching "^[0-9]+[KMGTPEkmgtpe]?$";
in
{
  options.services.nixdb = {
    enable = mkEnableOption "the reusable database instance stack";

    slice = {
      memoryHigh = mkOption {
        type = sizeType;
        default = "48G";
        description = "Combined database.slice memory pressure threshold.";
      };
      memoryMax = mkOption {
        type = sizeType;
        default = "64G";
        description = "Combined database.slice hard memory ceiling.";
      };
      memorySwapMax = mkOption {
        type = sizeType;
        default = "0";
        description = "Combined database.slice swap ceiling.";
      };
    };

    operator = {
      enable = mkEnableOption "the nixdb operator CLI" // {
        default = true;
      };
      configRoot = mkOption {
        type = types.strMatching "^/.*";
        default = "/etc/nixos";
        description = "Downstream host flake checkout operated by nixdb.";
      };
      flakeHost = mkOption {
        type = types.nonEmptyStr;
        default = config.networking.hostName;
        description = "Attribute name under nixosConfigurations in the downstream flake.";
      };
      inventoryFile = mkOption {
        type = types.nonEmptyStr;
        default = "databases.nix";
        description = "Absolute inventory path or a path relative to configRoot.";
      };
      inputName = mkOption {
        type = types.nonEmptyStr;
        default = "nixdb";
        description = "Name of the nixdb input in the downstream flake.";
      };
      inputUrl = mkOption {
        type = types.nonEmptyStr;
        default = "github:MrShitFox/nixdb";
        description = "Base flake URL used for targeted nixdb input updates.";
      };
      releaseRepository = mkOption {
        type = types.nonEmptyStr;
        default = "https://github.com/MrShitFox/nixdb.git";
        description = "Public Git repository queried for stable release tags.";
      };
    };

    _internal.instances = mkOption {
      internal = true;
      default = [ ];
      description = "Normalized metadata registered by database engine modules.";
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption { type = types.nonEmptyStr; };
            kind = mkOption { type = types.nonEmptyStr; };
            serviceName = mkOption { type = types.nonEmptyStr; };
            dataDir = mkOption { type = types.strMatching "^/.*"; };
            mountPoint = mkOption { type = types.strMatching "^/.*"; };
            projectId = mkOption { type = types.ints.between 1 4294967295; };
            diskLimit = mkOption { type = sizeType; };
            ports = mkOption { type = types.listOf types.port; };
            firewallPorts = mkOption {
              type = types.listOf types.port;
              description = "Public TCP listener ports opened by the firewall.";
            };
            listeners = mkOption {
              default = [ ];
              description = "TCP listeners expected at runtime.";
              type = types.listOf (
                types.submodule {
                  options = {
                    address = mkOption { type = types.nonEmptyStr; };
                    port = mkOption { type = types.port; };
                  };
                }
              );
            };
            cpuWeight = mkOption { type = types.ints.between 1 10000; };
            memoryHigh = mkOption { type = sizeType; };
            memoryMax = mkOption { type = sizeType; };
            memorySwapMax = mkOption {
              type = sizeType;
              default = "0";
            };
            engineMemoryLimit = mkOption {
              type = types.nullOr sizeType;
              default = null;
              description = "Sanitized database-engine memory ceiling, if the engine has one.";
            };
            unixSockets = mkOption {
              type = types.listOf (types.strMatching "^/.*");
              default = [ ];
              description = "Unix-domain listener paths owned by the instance.";
            };
            internalCache = mkOption {
              default = null;
              description = "Sanitized engine cache/buffer metadata for operators.";
              type = types.nullOr (
                types.submodule {
                  options = {
                    kind = mkOption { type = types.nonEmptyStr; };
                    value = mkOption { type = types.nonEmptyStr; };
                  };
                }
              );
            };
            engineMetadata = mkOption {
              type = types.attrs;
              default = { };
              description = "Sanitized engine-specific operator metadata.";
            };
          };
        }
      );
    };

    _internal.healthCredentials = mkOption {
      internal = true;
      default = [ ];
      description = "Root-only normalized credentials used by health probes.";
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption { type = types.nonEmptyStr; };
            engine = mkOption { type = types.nonEmptyStr; };
            address = mkOption { type = types.nonEmptyStr; };
            username = mkOption { type = types.str; };
            password = mkOption { type = types.str; };
            ports = mkOption { type = types.attrsOf types.port; };
            unixSocket = mkOption {
              type = types.nullOr (types.strMatching "^/.*");
              default = null;
              description = "Optional Redis Unix-domain socket used by health probes when TCP is disabled.";
            };
            authenticated = mkOption {
              type = types.bool;
              default = true;
            };
            tls = mkOption {
              type = types.attrs;
              default = { };
            };
          };
        }
      );
    };

    _internal.runtimeManifest = mkOption {
      internal = true;
      readOnly = true;
      type = types.attrs;
      description = "Sanitized evaluated runtime manifest consumed by the operator CLI.";
    };
  };
}
