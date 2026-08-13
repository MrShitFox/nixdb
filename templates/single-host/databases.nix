# SPDX-License-Identifier: GPL-3.0-or-later
{ ... }:

{
  services.nixdb = {
    enable = true;
    operator = {
      configRoot = "/etc/nixos";
      flakeHost = "db-host";
      inventoryFile = "databases.nix";
    };

    # Add MongoDB, MySQL, Manticore, Redis, or Dragonfly instances here. Start
    # from the nixdb examples and replace all CHANGE_ME values before deployment.
  };
}
