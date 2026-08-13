# SPDX-License-Identifier: GPL-3.0-or-later
#
# Public Redis examples. The declared mountPoint must be XFS with prjquota in
# the consuming NixOS configuration; replace every CHANGE_ME before deploy.
{ ... }:

{
  services.nixdb.redis.instances = {
    # A. Cache: no persistence, eviction at the engine limit.
    cache = {
      dataDir = "/srv/nixdb/redis/cache";
      mountPoint = "/";
      projectId = 2101;
      diskLimit = "10G";
      port = 6379;
      maxMemory = "2G";
      maxMemoryPolicy = "allkeys-lru";
      persistence.saveRules = [ ];
      memoryHigh = "2500M";
      memoryMax = "3G";
      cpuWeight = 120;
    };

    # B. Durable: AOF every second, retaining the documented RDB defaults.
    durable = {
      dataDir = "/srv/nixdb/redis/durable";
      mountPoint = "/";
      projectId = 2102;
      diskLimit = "20G";
      port = 6380;
      maxMemory = "2G";
      persistence = {
        appendOnly = true;
        appendFsync = "everysec";
      };
      authentication.password = "CHANGE_ME";
      memoryHigh = "2500M";
      memoryMax = "3G";
      cpuWeight = 120;
    };

    # C. Paranoid durability: explicitly request fsync for each AOF write.
    paranoid = {
      dataDir = "/srv/nixdb/redis/paranoid";
      mountPoint = "/";
      projectId = 2103;
      diskLimit = "20G";
      port = 6381;
      maxMemory = "1G";
      persistence = {
        appendOnly = true;
        appendFsync = "always";
      };
      authentication.password = "CHANGE_ME";
      memoryHigh = "1200M";
      memoryMax = "1500M";
      cpuWeight = 100;
    };

    # D. ACL: the generated ACL file keeps the default user disabled and adds
    # an application user with only a namespaced key pattern.
    acl = {
      dataDir = "/srv/nixdb/redis/acl";
      mountPoint = "/";
      projectId = 2104;
      diskLimit = "10G";
      port = 6382;
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

    # E. Native escape hatch: this Redis 8 directive is deliberately not a
    # nixdb option. A raw key that collides with a managed directive is an
    # evaluation error, never a silent override.
    advanced = {
      dataDir = "/srv/nixdb/redis/advanced";
      mountPoint = "/";
      projectId = 2105;
      diskLimit = "10G";
      port = 6383;
      maxMemory = "512M";
      extraConfig = {
        "notify-keyspace-events" = "Ex";
      };
      authentication.password = "CHANGE_ME";
      memoryHigh = "640M";
      memoryMax = "768M";
      cpuWeight = 100;
    };
  };
}
