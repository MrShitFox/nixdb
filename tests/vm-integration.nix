# SPDX-License-Identifier: GPL-3.0-or-later
{
  pkgs,
  nixdbModule,
}:

pkgs.testers.runNixOSTest {
  name = "nixdb-operator-integration";
  nodes.machine =
    { lib, pkgs, ... }:
    {
      imports = [ nixdbModule ];
      environment.systemPackages = [
        pkgs.jq
        pkgs.redis
        pkgs.xfsprogs
      ];

      # The extra disk is deliberately formatted inside testScript.  This lets
      # the ordinary nixdb XFS/prjquota unit run unchanged and makes the VM
      # exercise quota setup as well as both engine lifecycles.
      virtualisation = {
        memorySize = 2048;
        emptyDiskImages = [
          {
            size = 1024;
            driveConfig.deviceExtraOpts.serial = "nixdb-xfs";
          }
        ];
      };
      boot.supportedFilesystems = [ "xfs" ];
      virtualisation.fileSystems."/var/lib/nixdb-test" = {
        device = "/dev/disk/by-id/virtio-nixdb-xfs";
        fsType = "xfs";
        options = [
          "prjquota"
          "noauto"
        ];
      };

      services.nixdb = {
        enable = true;
        slice = {
          memoryHigh = "1200M";
          memoryMax = "1500M";
          memorySwapMax = "0";
        };
        mongodb.enable = false;
        mysql.enable = false;
        manticore.enable = false;
        redis.instances.redis-vm = {
          dataDir = "/var/lib/nixdb-test/redis";
          mountPoint = "/var/lib/nixdb-test";
          projectId = 3001;
          diskLimit = "128M";
          port = 16391;
          maxMemory = "512M";
          maxMemoryPolicy = "allkeys-lru";
          cpuWeight = 120;
          memoryHigh = "640M";
          memoryMax = "768M";
          memorySwapMax = "0";
          authentication = {
            password = "VM_REDIS_PASSWORD_NIXDB_TEST";
            users.vm-reader = {
              password = "VM_REDIS_READER_PASSWORD_NIXDB_TEST";
              commands = [ "+@read" ];
              keys = [ "~vm:*" ];
              channels = [ "&vm:*" ];
            };
          };
          persistence = {
            appendOnly = true;
            appendFsync = "always";
          };
        };
        redis.instances.redis-socket-vm = {
          dataDir = "/var/lib/nixdb-test/redis-socket";
          mountPoint = "/var/lib/nixdb-test";
          projectId = 3003;
          diskLimit = "64M";
          port = null;
          unixSocket = "/run/redis-socket-vm/redis.sock";
          maxMemory = "128M";
          maxMemoryPolicy = "noeviction";
          cpuWeight = 100;
          memoryHigh = "192M";
          memoryMax = "256M";
          memorySwapMax = "0";
          authentication.password = "VM_REDIS_SOCKET_PASSWORD_NIXDB_TEST";
          persistence.saveRules = [ ];
        };
        dragonfly.instances.dragonfly-vm = {
          dataDir = "/var/lib/nixdb-test/dragonfly";
          mountPoint = "/var/lib/nixdb-test";
          projectId = 3002;
          diskLimit = "128M";
          port = 16392;
          maxMemory = "512M";
          cacheMode = false;
          proactorThreads = 1;
          cpuWeight = 130;
          memoryHigh = "640M";
          memoryMax = "768M";
          memorySwapMax = "0";
          authentication = {
            password = "VM_DRAGONFLY_PASSWORD_NIXDB_TEST";
            users.vm-reader = {
              password = "VM_DRAGONFLY_READER_PASSWORD_NIXDB_TEST";
              commands = [ "+@read" ];
              keys = [ "~vm:*" ];
              channels = [ "&vm:*" ];
            };
          };
          persistence = {
            dbFilename = "snapshot";
            snapshotCron = "";
          };
        };
        operator = {
          enable = true;
          configRoot = "/etc/nixdb-test-host";
          flakeHost = "machine";
          inventoryFile = "inventory.nix";
        };
      };

      # Do not try to start database services before testScript has created
      # the disposable XFS filesystem.  testScript starts databases.target
      # after formatting/mounting; the production quota service is not mocked.
      systemd.targets.databases.wantedBy = lib.mkForce [ ];
      systemd.tmpfiles.rules = [ "d /etc/nixdb-test-host 0755 root root -" ];
    };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkfs.xfs -f /dev/disk/by-id/virtio-nixdb-xfs")
    machine.succeed("systemctl start 'var-lib-nixdb\\x2dtest.mount'")
    machine.succeed("findmnt -n -o FSTYPE --target /var/lib/nixdb-test | grep -Fx xfs")
    machine.succeed("findmnt -n -o OPTIONS --target /var/lib/nixdb-test | grep -Eq '(^|,)prjquota(,|$)'")
    machine.succeed("systemctl start databases.target")
    machine.wait_for_unit("redis-vm.service")
    machine.wait_for_unit("redis-socket-vm.service")
    machine.wait_for_unit("dragonfly-vm.service")
    machine.succeed("systemctl cat database.slice")
    machine.succeed("test -r /etc/nixdb/manifest.json")
    machine.succeed("test -r /etc/nixdb/operator.json")
    machine.succeed("test $(stat -c %a /etc/nixdb/health-credentials.json) = 400")
    machine.succeed("jq -e '.schemaVersion == 1 and (.instances | length == 3)' /etc/nixdb/manifest.json")
    machine.succeed("! grep -F VM_REDIS_PASSWORD_NIXDB_TEST /etc/nixdb/manifest.json")
    machine.succeed("! grep -F VM_REDIS_READER_PASSWORD_NIXDB_TEST /etc/nixdb/manifest.json")
    machine.succeed("! grep -F VM_REDIS_SOCKET_PASSWORD_NIXDB_TEST /etc/nixdb/manifest.json")
    machine.succeed("! grep -F VM_DRAGONFLY_PASSWORD_NIXDB_TEST /etc/nixdb/manifest.json")
    machine.succeed("! grep -F VM_DRAGONFLY_READER_PASSWORD_NIXDB_TEST /etc/nixdb/manifest.json")
    machine.succeed("redis-cli -p 16391 --user nixdb-admin --pass VM_REDIS_PASSWORD_NIXDB_TEST PING | grep -Fx PONG")
    machine.succeed("redis-cli -p 16391 --user nixdb-admin --pass VM_REDIS_PASSWORD_NIXDB_TEST SET vm:reader readable")
    machine.succeed("redis-cli -p 16391 --user vm-reader --pass VM_REDIS_READER_PASSWORD_NIXDB_TEST GET vm:reader | grep -Fx readable")
    machine.succeed("redis-cli -p 16391 --user vm-reader --pass VM_REDIS_READER_PASSWORD_NIXDB_TEST SET vm:reader denied 2>&1 | grep -F NOPERM")
    machine.succeed("redis-cli -p 16391 --user vm-reader --pass WRONG_PASSWORD GET vm:reader 2>&1 | grep -Eqi 'WRONGPASS|NOAUTH'")
    machine.succeed("redis-cli -p 16391 --user nixdb-admin --pass VM_REDIS_PASSWORD_NIXDB_TEST --raw MODULE LIST | grep -Ex '(bf|search|ReJSON|timeseries)'")
    machine.succeed("redis-cli -p 16391 --user nixdb-admin --pass VM_REDIS_PASSWORD_NIXDB_TEST CONFIG GET maxmemory | grep -Fx 512000000")
    machine.succeed("redis-cli -p 16391 --user nixdb-admin --pass VM_REDIS_PASSWORD_NIXDB_TEST SET vm:redis persisted")
    machine.succeed("redis-cli -p 16391 --user nixdb-admin --pass VM_REDIS_PASSWORD_NIXDB_TEST SAVE")
    machine.succeed("systemctl restart redis-vm.service")
    machine.wait_for_unit("redis-vm.service")
    machine.succeed("redis-cli -p 16391 --user nixdb-admin --pass VM_REDIS_PASSWORD_NIXDB_TEST GET vm:redis | grep -Fx persisted")
    machine.succeed("test -S /run/redis-socket-vm/redis.sock")
    machine.succeed("redis-cli -s /run/redis-socket-vm/redis.sock --user nixdb-admin --pass VM_REDIS_SOCKET_PASSWORD_NIXDB_TEST PING | grep -Fx PONG")
    machine.succeed("redis-cli -p 16392 --user nixdb-admin --pass VM_DRAGONFLY_PASSWORD_NIXDB_TEST PING | grep -Fx PONG")
    machine.succeed("redis-cli -p 16392 --user nixdb-admin --pass VM_DRAGONFLY_PASSWORD_NIXDB_TEST SET vm:reader readable")
    machine.succeed("redis-cli -p 16392 --user vm-reader --pass VM_DRAGONFLY_READER_PASSWORD_NIXDB_TEST GET vm:reader | grep -Fx readable")
    machine.succeed("redis-cli -p 16392 --user vm-reader --pass VM_DRAGONFLY_READER_PASSWORD_NIXDB_TEST SET vm:reader denied 2>&1 | grep -F NOPERM")
    machine.succeed("redis-cli -p 16392 --user vm-reader --pass WRONG_PASSWORD GET vm:reader 2>&1 | grep -Eqi 'WRONGPASS|NOAUTH'")
    machine.succeed("redis-cli -p 16392 --user nixdb-admin --pass VM_DRAGONFLY_PASSWORD_NIXDB_TEST CONFIG GET maxmemory | grep -Fx 536870912")
    machine.succeed("redis-cli -p 16392 --user nixdb-admin --pass VM_DRAGONFLY_PASSWORD_NIXDB_TEST SET vm:dragonfly persisted")
    machine.succeed("redis-cli -p 16392 --user nixdb-admin --pass VM_DRAGONFLY_PASSWORD_NIXDB_TEST SAVE")
    machine.succeed("test -n \"$(find /var/lib/nixdb-test/dragonfly -type f -name 'snapshot*' -print -quit)\"")
    machine.succeed("systemctl restart dragonfly-vm.service")
    machine.wait_for_unit("dragonfly-vm.service")
    machine.succeed("redis-cli -p 16392 --user nixdb-admin --pass VM_DRAGONFLY_PASSWORD_NIXDB_TEST GET vm:dragonfly | grep -Fx persisted")
    machine.succeed("command -v nixdb")
    machine.succeed("nixdb status")
    machine.succeed("nixdb status --json | jq -e '.sourceCheckout.state == \"not a Git checkout\"'")
    machine.succeed("nixdb versions --json | jq -e '.redis.declared == \"8.10.0\" and .dragonfly.declared == \"1.40.1\"'")
    machine.succeed("nixdb resources")
    machine.succeed("nixdb config")
    machine.succeed("nixdb health")
    machine.succeed("nixdb restart redis-vm")
    machine.succeed("nixdb wait redis-socket-vm")
    machine.succeed("nixdb wait dragonfly-vm")
    machine.succeed("nixdb doctor")
  '';
}
