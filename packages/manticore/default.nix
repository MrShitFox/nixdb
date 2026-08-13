{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  dpkg,
  makeWrapper,
  bash,
  coreutils,
  curl,
  gawk,
  openssl,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "manticoresearch-bundle";
  version = "28.6.6";

  src = fetchurl {
    url = "https://repo.manticoresearch.com/repository/manticoresearch_jammy/dists/jammy/main/binary-amd64/manticore_28.6.6-26073104-e5feb9932_amd64.deb";
    hash = "sha256-uotL1k2m5IrYrdnPPS389k0dY6QI19ynVidHHa5ivJM=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    curl
    openssl
    zlib
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" source
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -a source/usr/* "$out/"
    substituteInPlace "$out/bin/manticore-backup" \
      --replace-fail 'executor=$(which manticore-executor 2> /dev/null)' \
        'executor=$(command -v manticore-executor 2> /dev/null)'
    substituteInPlace "$out/bin/manticore-load" \
      --replace-fail '#!/usr/bin/env manticore-executor' \
        "#!$out/bin/manticore-executor"
    patchShebangs "$out/bin" "$out/share/manticore/modules"
    ln -s ../share/manticore/modules/manticore-load "$out/bin/src"
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/searchd" \
      --set MANTICORE_MODULES "$out/share/manticore/modules" \
      --set MANTICORE_CURL_LIB "${lib.getLib curl}/lib/libcurl.so" \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          coreutils
          curl
          gawk
        ]
      }:$out/bin
    wrapProgram "$out/bin/manticore-backup" \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          coreutils
        ]
      }:$out/bin
    wrapProgram "$out/bin/manticore-load" \
      --prefix PATH : "$out/bin"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/searchd" --version | grep -F "Manticore ${finalAttrs.version}"
    test -x "$out/bin/manticore-executor"
    test -f "$out/share/manticore/modules/manticore-buddy/src/main.php"
    test -f "$out/share/manticore/modules/manticore-buddy/manticore-buddy.phar"
    "$out/bin/manticore-backup" --version \
      | grep -F "Manticore Backup version: ${finalAttrs.passthru.componentVersions.backup}"
    test "$(cat "$out/share/manticore/modules/manticore-load/APP_VERSION")" \
      = "${finalAttrs.passthru.componentVersions.load}"
  '';

  passthru = {
    sourcePackageVersion = "28.6.6-26073104-e5feb9932";
    componentVersions = {
      search = "28.6.6";
      buddy = "4.2.0+26063013-dc2f8c9f";
      columnar = "13.8.3+26072200-7925d71c";
      secondary = "13.8.3+26072200-7925d71c";
      knn = "13.8.3+26072200-7925d71c";
      embeddings = "1.1.1+26072122-7925d71";
      executor = "1.4.2+26031911-95e5ef78";
      backup = "1.10.2+26072909-4693a185";
      load = "1.25.0+26050511-832198ca";
      tzdata = "1.0.1-250708-4dfa71e";
      galera = "3.37";
    };
  };

  meta = {
    description = "Manticore Search with its upstream-compatible runtime components";
    homepage = "https://manticoresearch.com";
    changelog = "https://manual.manticoresearch.com/Changelog#version-2866";
    license = with lib.licenses; [
      gpl3Plus
      gpl2Only
      lgpl21Plus
      asl20
      php301
      mit
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "searchd";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
