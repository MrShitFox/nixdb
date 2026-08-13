# SPDX-License-Identifier: GPL-3.0-or-later
{ ... }:

{
  networking.hostName = "db-host";
  system.stateVersion = "26.05";

  # Replace these illustrative filesystem declarations with the real host's
  # generated hardware configuration. Every nixdb data mount must be XFS with
  # project quotas enabled.
  fileSystems."/" = {
    device = "/dev/disk/by-label/example-root";
    fsType = "xfs";
    options = [ "prjquota" ];
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
