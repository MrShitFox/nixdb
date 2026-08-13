{ config, lib, ... }:

lib.mkIf config.services.nixdb.enable {
  networking.firewall.allowedTCPPorts = lib.concatMap (
    instance: instance.firewallPorts
  ) config.services.nixdb._internal.instances;
}
