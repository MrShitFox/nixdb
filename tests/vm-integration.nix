# SPDX-License-Identifier: GPL-3.0-or-later
{
  pkgs,
  nixdbModule,
}:

pkgs.testers.runNixOSTest {
  name = "nixdb-operator-integration";
  nodes.machine = {
    imports = [ nixdbModule ];
    environment.systemPackages = [ pkgs.jq ];
    services.nixdb = {
      enable = true;
      mongodb.enable = false;
      mysql.enable = false;
      manticore.enable = false;
      operator = {
        enable = true;
        configRoot = "/etc/nixdb-test-host";
        flakeHost = "machine";
        inventoryFile = "inventory.nix";
      };
    };
    systemd.tmpfiles.rules = [ "d /etc/nixdb-test-host 0755 root root -" ];
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("systemctl cat database.slice")
    machine.succeed("test -r /etc/nixdb/manifest.json")
    machine.succeed("test -r /etc/nixdb/operator.json")
    machine.succeed("test $(stat -c %a /etc/nixdb/health-credentials.json) = 400")
    machine.succeed("jq -e '.schemaVersion == 1 and (.instances | length == 0)' /etc/nixdb/manifest.json")
    machine.succeed("! grep -F SUPER_SECRET_NIXDB_TEST_VALUE_9f31 /etc/nixdb/manifest.json")
    machine.succeed("command -v nixdb")
    machine.succeed("nixdb status")
    machine.succeed("nixdb status --json | jq -e '.sourceCheckout.state == \"not a Git checkout\"'")
    machine.succeed("nixdb versions --json | jq -e '.mongodb.declared != null'")
    machine.succeed("nixdb resources")
    machine.succeed("nixdb config")
    machine.succeed("nixdb doctor")
  '';
}
