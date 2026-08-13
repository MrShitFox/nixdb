{ config, lib, ... }:

let
  cfg = config.services.nixdb;
  instances = cfg._internal.instances;
  unique = values: builtins.length values == builtins.length (lib.unique values);
  inherit (import ../../../lib/sizes.nix { inherit lib; }) parseSize;
  memorySane = instance: parseSize instance.memoryHigh <= parseSize instance.memoryMax;
  dataDirOnMount =
    instance:
    let
      isStrictChild =
        if instance.mountPoint == "/" then
          instance.dataDir != "/"
        else
          lib.hasPrefix "${instance.mountPoint}/" instance.dataDir;
      nestedMounts = lib.filter (
        mountPoint:
        mountPoint != "/"
        && mountPoint != instance.mountPoint
        && lib.hasPrefix "${mountPoint}/" instance.dataDir
      ) (builtins.attrNames config.fileSystems);
    in
    isStrictChild && nestedMounts == [ ];
  mountIsXfs =
    instance:
    let
      mount = config.fileSystems.${instance.mountPoint} or { };
    in
    (mount.fsType or null) == "xfs";
  mountHasProjectQuotas =
    instance:
    let
      mount = config.fileSystems.${instance.mountPoint} or { };
    in
    builtins.elem "prjquota" (mount.options or [ ]);
  firewallPortsRegistered =
    instance: lib.all (port: builtins.elem port instance.ports) instance.firewallPorts;
  serviceNameSafe =
    instance:
    builtins.match "^[a-z][a-z0-9_-]*$" instance.serviceName != null
    && builtins.stringLength instance.serviceName <= 31;
in
lib.mkIf cfg.enable {
  assertions = [
    {
      assertion = unique (map (instance: instance.projectId) instances);
      message = "services.nixdb: XFS project IDs must be unique across all engines.";
    }
    {
      assertion = unique (lib.concatMap (instance: instance.ports) instances);
      message = "services.nixdb: TCP ports must be unique across all engines.";
    }
    {
      assertion = unique (map (instance: instance.dataDir) instances);
      message = "services.nixdb: data directories must be unique across all engines.";
    }
    {
      assertion = unique (lib.concatMap (instance: instance.unixSockets) instances);
      message = "services.nixdb: Unix socket paths must be unique across all engines.";
    }
    {
      assertion = unique (map (instance: instance.name) instances);
      message = "services.nixdb: normalized instance names must be unique across all engines.";
    }
    {
      assertion = unique (map (instance: instance.serviceName) instances);
      message = "services.nixdb: generated systemd service names must be unique across all engines.";
    }
    {
      assertion = lib.all (instance: builtins.hasAttr instance.mountPoint config.fileSystems) instances;
      message = "services.nixdb: every instance mountPoint must name a declared NixOS filesystem.";
    }
    {
      assertion = lib.all dataDirOnMount instances;
      message = "services.nixdb: every dataDir must be a strict child of its declared mountPoint.";
    }
    {
      assertion = lib.all mountIsXfs instances;
      message = "services.nixdb: every database mountPoint must use XFS.";
    }
    {
      assertion = lib.all mountHasProjectQuotas instances;
      message = "services.nixdb: every database mountPoint must enable the prjquota option.";
    }
    {
      assertion = lib.all firewallPortsRegistered instances;
      message = "services.nixdb: every firewallPort must also be registered in the instance ports list.";
    }
    {
      assertion = lib.all serviceNameSafe instances;
      message = "services.nixdb: service names must be safe system-user names of at most 31 characters.";
    }
    {
      assertion = lib.all memorySane instances;
      message = "services.nixdb: every instance must have memoryHigh less than or equal to memoryMax.";
    }
    {
      assertion = parseSize cfg.slice.memoryHigh <= parseSize cfg.slice.memoryMax;
      message = "services.nixdb: database.slice memoryHigh must be less than or equal to memoryMax.";
    }
  ];
}
