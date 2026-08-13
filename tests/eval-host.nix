# SPDX-License-Identifier: GPL-3.0-or-later
{ lib, ... }:

{
  boot.isContainer = true;
  networking.hostName = "db-host";
  system.stateVersion = "26.05";

  fileSystems."/" = {
    device = "/dev/disk/by-label/example-root";
    fsType = "xfs";
    options = [ "prjquota" ];
  };

  services.nixdb = {
    enable = true;
    slice = {
      memoryHigh = "4G";
      memoryMax = "6G";
      memorySwapMax = "0";
    };
    operator.enable = false;

    mongodb.instances.mongo-example = {
      dataDir = "/srv/databases/mongodb/mongo-example";
      mountPoint = "/";
      projectId = 2001;
      diskLimit = "2G";
      port = 27017;
      adminUser = "dbadmin";
      password = "CHANGE_ME";
      cpuWeight = 100;
      cacheGB = 1;
      memoryHigh = "1G";
      memoryMax = "2G";
    };

    mysql.instances.mysql-example = {
      dataDir = "/srv/databases/mysql/mysql-example";
      mountPoint = "/";
      projectId = 2002;
      diskLimit = "2G";
      port = 3306;
      adminUser = "dbadmin";
      password = "CHANGE_ME";
      cpuWeight = 100;
      bufferPool = "1G";
      maxConnections = 100;
      memoryHigh = "1G";
      memoryMax = "2G";
    };

    manticore.instances.search-example = {
      dataDir = "/srv/databases/manticore/search-example";
      mountPoint = "/";
      projectId = 2003;
      diskLimit = "2G";
      sqlPort = 9306;
      httpPort = 9308;
      adminUser = "dbadmin";
      password = "CHANGE_ME";
      cpuWeight = 100;
      memoryHigh = "1G";
      memoryMax = "2G";
    };
  };
}
