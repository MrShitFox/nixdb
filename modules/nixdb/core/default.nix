{
  config,
  lib,
  nixdbCli,
  nixdbRelease,
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
  inventoryPath =
    if lib.hasPrefix "/" cfg.operator.inventoryFile then
      cfg.operator.inventoryFile
    else
      "${cfg.operator.configRoot}/${cfg.operator.inventoryFile}";
  manifest = {
    schemaVersion = 1;
    framework = {
      inherit (nixdbRelease) version revision;
    };
    operator = {
      configRoot = cfg.operator.configRoot;
      flakeHost = cfg.operator.flakeHost;
      configHint = inventoryPath;
      inputName = cfg.operator.inputName;
      inputUrl = cfg.operator.inputUrl;
      releaseRepository = cfg.operator.releaseRepository;
    };
    slice = cfg.slice;
    versions = {
      mongodb = cfg.mongodb.declaredVersion;
      mysql = cfg.mysql.declaredVersion;
      manticore = cfg.manticore.declaredVersion;
      manticoreComponents = cfg.manticore.componentVersions;
    };
    instances = map (
      instance:
      (builtins.removeAttrs instance [
        "kind"
        "firewallPorts"
      ])
      // {
        engine = instance.kind;
      }
    ) instances;
  };
in
lib.mkIf cfg.enable {
  services.nixdb._internal.runtimeManifest = manifest;

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

  systemd.tmpfiles.rules = lib.mkIf cfg.operator.enable [
    "d /var/lib/nixdb 0700 root root -"
    "d /var/lib/nixdb/generations 0700 root root -"
  ];

  environment.etc."nixdb/operator.json" = lib.mkIf cfg.operator.enable {
    mode = "0444";
    text = builtins.toJSON {
      configRoot = cfg.operator.configRoot;
      flakeHost = cfg.operator.flakeHost;
      inherit inventoryPath;
      inputName = cfg.operator.inputName;
      inputUrl = cfg.operator.inputUrl;
      releaseRepository = cfg.operator.releaseRepository;
      frameworkVersion = nixdbRelease.version;
      frameworkRevision = nixdbRelease.revision;
      manifestPath = "/etc/nixdb/manifest.json";
      healthCredentialsPath = "/etc/nixdb/health-credentials.json";
    };
  };

  environment.etc."nixdb/manifest.json" = lib.mkIf cfg.operator.enable {
    mode = "0444";
    text = builtins.toJSON manifest;
  };

  environment.etc."nixdb/health-credentials.json" = lib.mkIf cfg.operator.enable {
    mode = "0400";
    text = builtins.toJSON {
      schemaVersion = 1;
      instances = cfg._internal.healthCredentials;
    };
  };
}
