{ ... }:

{
  imports = [
    ./core
    ./core/options.nix
    ./core/assertions.nix
    ./core/firewall.nix
    ./core/quotas.nix
    ./core/slice.nix
    ./engines/mongodb.nix
    ./engines/mysql.nix
    ./engines/manticore.nix
  ];
}
