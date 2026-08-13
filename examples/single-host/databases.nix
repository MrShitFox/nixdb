# SPDX-License-Identifier: GPL-3.0-or-later
{ ... }:

{
  services.nixdb = {
    enable = true;
    slice = {
      memoryHigh = "8G";
      memoryMax = "12G";
      memorySwapMax = "0";
    };

    operator = {
      configRoot = "/etc/nixos";
      flakeHost = "db-host";
      inventoryFile = "databases.nix";
    };

    mongodb.instances.mongo-example = {
      dataDir = "/srv/databases/mongodb/mongo-example";
      mountPoint = "/";
      projectId = 2001;
      diskLimit = "10G";
      port = 27017;
      adminUser = "dbadmin";
      password = "CHANGE_ME";
      cpuWeight = 100;
      cacheGB = 1;
      memoryHigh = "2G";
      memoryMax = "3G";
    };

    mysql.instances.mysql-example = {
      dataDir = "/srv/databases/mysql/mysql-example";
      mountPoint = "/";
      projectId = 2002;
      diskLimit = "10G";
      port = 3306;
      adminUser = "dbadmin";
      password = "CHANGE_ME";
      cpuWeight = 100;
      bufferPool = "1G";
      maxConnections = 100;
      memoryHigh = "2G";
      memoryMax = "3G";
    };

    manticore.instances.search-example = {
      dataDir = "/srv/databases/manticore/search-example";
      mountPoint = "/";
      projectId = 2003;
      diskLimit = "10G";
      sqlPort = 9306;
      httpPort = 9308;
      adminUser = "dbadmin";
      password = "CHANGE_ME";
      cpuWeight = 100;
      memoryHigh = "2G";
      memoryMax = "3G";
    };

    redis.instances.redis-cache = {
      dataDir = "/srv/databases/redis/cache";
      mountPoint = "/";
      projectId = 2004;
      diskLimit = "20G";
      port = 6379;
      maxMemory = "2G";
      maxMemoryPolicy = "allkeys-lru";
      persistence.saveRules = [ ];
      memoryHigh = "2500M";
      memoryMax = "3G";
    };

    redis.instances.redis-paranoid = {
      dataDir = "/srv/databases/redis/paranoid";
      mountPoint = "/";
      projectId = 2005;
      diskLimit = "20G";
      port = 6380;
      maxMemory = "1G";
      persistence = {
        appendOnly = true;
        appendFsync = "always";
      };
      authentication.password = "CHANGE_ME";
      memoryHigh = "1200M";
      memoryMax = "1500M";
    };

    dragonfly.instances.dragonfly-store = {
      dataDir = "/srv/databases/dragonfly/store";
      mountPoint = "/";
      projectId = 2006;
      diskLimit = "20G";
      port = 6381;
      maxMemory = "2G";
      cacheMode = false;
      persistence.snapshotCron = "*/5 * * * *";
      memoryHigh = "2500M";
      memoryMax = "3G";
    };

    dragonfly.instances.dragonfly-cache = {
      dataDir = "/srv/databases/dragonfly/cache";
      mountPoint = "/";
      projectId = 2007;
      diskLimit = "20G";
      port = 6382;
      maxMemory = "1G";
      cacheMode = true;
      extraFlags = {
        num_shards = 2;
      };
      memoryHigh = "1200M";
      memoryMax = "1500M";
    };
  };
}
