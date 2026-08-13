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
  };
}
