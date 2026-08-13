{
  config,
  lib,
  nixdbCli,
  nixdbRelease,
  nixdbVersions,
  ...
}:

let
  cfg = config.services.nixdb;
  instances = cfg._internal.instances;
  instanceAttrs = builtins.listToAttrs (
    map (instance: {
      name = instance.serviceName;
      value = instance;
    }) instances
  );
  serviceUnits = map (instance: "${instance.serviceName}.service") instances;
in
lib.mkIf cfg.enable {
  users.groups = lib.mapAttrs (_: _: { }) instanceAttrs;
  users.users = lib.mapAttrs (name: instance: {
    isSystemUser = true;
    group = name;
    home = instance.dataDir;
    createHome = false;
  }) instanceAttrs;

  systemd.targets.databases = {
    description = "All database instances";
    wantedBy = [ "multi-user.target" ];
    requires = serviceUnits;
    after = serviceUnits;
  };

  environment.systemPackages = lib.optional cfg.operator.enable nixdbCli;

  environment.etc."nixdb/operator.json" = lib.mkIf cfg.operator.enable {
    mode = "0444";
    text = builtins.toJSON {
      configRoot = cfg.operator.configRoot;
      flakeHost = cfg.operator.flakeHost;
      inventoryPath =
        if lib.hasPrefix "/" cfg.operator.inventoryFile then
          cfg.operator.inventoryFile
        else
          "${cfg.operator.configRoot}/${cfg.operator.inventoryFile}";
      inputName = cfg.operator.inputName;
      inputUrl = cfg.operator.inputUrl;
      releaseRepository = cfg.operator.releaseRepository;
      frameworkVersion = nixdbRelease.version;
      frameworkRevision = nixdbRelease.revision;
      versions = nixdbVersions;
    };
  };
}
