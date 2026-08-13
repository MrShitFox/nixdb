# SPDX-License-Identifier: GPL-3.0-or-later
{ ... }:

{
  networking.hostName = "db-host";
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  system.stateVersion = "26.05"; # Set this to the host's initial NixOS release.
}
