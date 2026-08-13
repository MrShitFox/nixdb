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
  gnutar,
  hostname,
  iproute2,
  jq,
  nix,
  netcat-openbsd,
  openssh,
  redis,
  systemd,
  util-linux,
  xfsprogs,
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
    gnutar
    hostname
    iproute2
    jq
    nix
    netcat-openbsd
    openssh
    redis
    systemd
    util-linux
    xfsprogs
  ];
  text = builtins.readFile ./nixdb;
  meta = {
    description = "Operator CLI for the nixdb NixOS database stack";
    license = lib.licenses.gpl3Plus;
    mainProgram = "nixdb";
  };
}
