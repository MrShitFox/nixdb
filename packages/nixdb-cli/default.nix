{
  lib,
  writeShellApplication,
  bash,
  coreutils,
  curl,
  findutils,
  gawk,
  git,
  gnugrep,
  gnused,
  hostname,
  iproute2,
  jq,
  nix,
  openssh,
  systemd,
  util-linux,
  xfsprogs,
  dbPackages,
}:

writeShellApplication {
  name = "nixdb";
  runtimeInputs = [
    bash
    coreutils
    curl
    findutils
    gawk
    git
    gnugrep
    gnused
    hostname
    iproute2
    jq
    nix
    openssh
    systemd
    util-linux
    xfsprogs
    dbPackages.mongodb
    dbPackages.mongosh
    dbPackages.mysql
    dbPackages.manticore
  ];
  text = builtins.readFile ./nixdb;
  meta = {
    description = "Operator CLI for the nixdb NixOS database stack";
    license = lib.licenses.gpl3Plus;
    mainProgram = "nixdb";
  };
}
