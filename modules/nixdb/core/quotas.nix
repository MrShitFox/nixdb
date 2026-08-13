{
  config,
  lib,
  pkgs,
  ...
}:

let
  q = lib.escapeShellArg;

  mkQuotaService =
    name: instance:
    lib.nameValuePair "db-quota-${name}" {
      description = "XFS quota for database instance ${name}";
      after = [ "local-fs.target" ];
      unitConfig.RequiresMountsFor = instance.mountPoint;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        ${pkgs.coreutils}/bin/mkdir -p ${q instance.dataDir}
        ${pkgs.coreutils}/bin/chown ${q "${name}:${name}"} ${q instance.dataDir}
        ${pkgs.coreutils}/bin/chmod 0700 ${q instance.dataDir}

        marker=${q "${instance.dataDir}/.xfs-project-${toString instance.projectId}"}
        if [ ! -e "$marker" ]; then
          ${pkgs.xfsprogs}/bin/xfs_quota \
            -x \
            -c ${q "project -s -p ${instance.dataDir} ${toString instance.projectId}"} \
            ${q instance.mountPoint}
          ${pkgs.coreutils}/bin/touch "$marker"
          ${pkgs.coreutils}/bin/chown ${q "${name}:${name}"} "$marker"
          ${pkgs.coreutils}/bin/chmod 0600 "$marker"
        fi

        ${pkgs.xfsprogs}/bin/xfs_quota \
          -x \
          -c ${q "limit -p bhard=${instance.diskLimit} ${toString instance.projectId}"} \
          ${q instance.mountPoint}
      '';
    };
in
lib.mkIf config.services.nixdb.enable {
  systemd.services = builtins.listToAttrs (
    map (
      instance: mkQuotaService instance.serviceName instance
    ) config.services.nixdb._internal.instances
  );
}
