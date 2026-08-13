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

    # Add MongoDB, MySQL, or Manticore instances here. Start from the examples
    # in the nixdb README and replace all CHANGE_ME values before deployment.
  };
}
