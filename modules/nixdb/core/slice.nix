{ config, lib, ... }:

lib.mkIf config.services.nixdb.enable {
  systemd.slices.database = {
    description = "All database instances";
    sliceConfig = {
      MemoryHigh = config.services.nixdb.slice.memoryHigh;
      MemoryMax = config.services.nixdb.slice.memoryMax;
      MemorySwapMax = config.services.nixdb.slice.memorySwapMax;
    };
  };
}
