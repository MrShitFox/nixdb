# SPDX-License-Identifier: GPL-3.0-or-later
#
# Public Dragonfly examples. The declared mountPoint must be XFS with prjquota
# in the consuming NixOS configuration; replace every CHANGE_ME before deploy.
{ ... }:

{
  services.nixdb.dragonfly.instances = {
    # A. Store mode is Dragonfly's default: cacheMode = false is explicit here.
    store = {
      dataDir = "/srv/nixdb/dragonfly/store";
      mountPoint = "/";
      projectId = 2201;
      diskLimit = "20G";
      port = 6391;
      maxMemory = "2G";
      cacheMode = false;
      authentication.password = "CHANGE_ME";
      memoryHigh = "2500M";
      memoryMax = "3G";
      cpuWeight = 120;
    };

    # B. Cache mode is intentionally visible in the manifest and CLI output.
    cache = {
      dataDir = "/srv/nixdb/dragonfly/cache";
      mountPoint = "/";
      projectId = 2202;
      diskLimit = "10G";
      port = 6392;
      maxMemory = "1G";
      cacheMode = true;
      authentication.password = "CHANGE_ME";
      memoryHigh = "1200M";
      memoryMax = "1500M";
      cpuWeight = 120;
    };

    # C. Snapshot persistence. Native Dragonfly snapshots use an extensionless
    # filename; set dfSnapshotFormat = false only for an RDB filename.
    snapshots = {
      dataDir = "/srv/nixdb/dragonfly/snapshots";
      mountPoint = "/";
      projectId = 2203;
      diskLimit = "20G";
      port = 6393;
      maxMemory = "1G";
      persistence = {
        dbFilename = "snapshot";
        snapshotCron = "*/5 * * * *";
      };
      authentication.password = "CHANGE_ME";
      memoryHigh = "1200M";
      memoryMax = "1500M";
      cpuWeight = 100;
    };

    # D. An opt-in local Memcached listener. It is not exposed through the
    # firewall unless memcached.openFirewall is set true explicitly.
    memcached = {
      dataDir = "/srv/nixdb/dragonfly/memcached";
      mountPoint = "/";
      projectId = 2204;
      diskLimit = "10G";
      port = 6394;
      maxMemory = "1G";
      memcached.port = 11221;
      authentication.password = "CHANGE_ME";
      memoryHigh = "1200M";
      memoryMax = "1500M";
      cpuWeight = 100;
    };

    # E. Redis-compatible ACL users, rendered to Dragonfly's --aclfile.
    acl = {
      dataDir = "/srv/nixdb/dragonfly/acl";
      mountPoint = "/";
      projectId = 2205;
      diskLimit = "10G";
      port = 6395;
      maxMemory = "512M";
      authentication = {
        password = "CHANGE_ME";
        users.app-reader = {
          password = "CHANGE_ME";
          commands = [ "+@read" ];
          keys = [ "~app:*" ];
          channels = [ "&app:*" ];
        };
      };
      memoryHigh = "640M";
      memoryMax = "768M";
      cpuWeight = 100;
    };

    # F. Native escape hatch: num_shards is supported by the pinned Dragonfly
    # binary but intentionally not part of nixdb's stable typed surface.
    advanced = {
      dataDir = "/srv/nixdb/dragonfly/advanced";
      mountPoint = "/";
      projectId = 2206;
      diskLimit = "10G";
      port = 6396;
      maxMemory = "1G";
      extraFlags.num_shards = 2;
      authentication.password = "CHANGE_ME";
      memoryHigh = "1200M";
      memoryMax = "1500M";
      cpuWeight = 100;
    };
  };
}
