{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libgbm,
  libsecret,
  libxkbcommon,
  nspr,
  nss,
  pango,
  systemd,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libdrm,
  libGL,
  vulkan-loader,
  wayland,
  libnotify,
  lsof,
}:

# Anytype from the official .deb (prebuilt Electron + backend), instead of the
# nixpkgs source build. That build compiles on every machine (unfree, so uncached)
# and installs the whole node_modules tree, 2.5 GiB; this one is ~0.7 GiB.
#
# Update: change `version`, set `hash = lib.fakeHash`, build once, paste the
# printed hash. Release list: https://github.com/anyproto/anytype-ts/releases
stdenv.mkDerivation (finalAttrs: {
  pname = "anytype-bin";
  version = "0.57.7";

  src = fetchurl {
    url = "https://github.com/anyproto/anytype-ts/releases/download/v${finalAttrs.version}/anytype_${finalAttrs.version}_amd64.deb";
    hash = "sha256-FryAE2LVhsFnObqFab+c6O+Ar1lzmIesgUoSIzqamEo=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  # Libraries the Electron binary links against (found by autoPatchelfHook).
  buildInputs = [
    alsa-lib
    at-spi2-core # atk, atk-bridge, atspi
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libgbm
    libsecret # keytar.node
    libxkbcommon
    nspr
    nss
    pango
    (lib.getLib systemd) # libudev
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    stdenv.cc.cc.lib
  ];

  # Chromium dlopen()s these at runtime, so they are not in the ELF NEEDED list.
  runtimeDependencies = [
    (lib.getLib systemd)
    libGL
    vulkan-loader
    wayland
    libdrm
    libnotify
    libsecret
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  # Electron binaries must not be stripped.
  dontStrip = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin $out/share
    cp -r opt/Anytype $out/lib/anytype
    cp -r usr/share/icons usr/share/applications $out/share/

    # The deb's updater would download a ~240 MB .deb and try to install it with
    # the system package manager, which cannot work in the Nix store. Without
    # app-update.yml it has no update source, so it never downloads anything.
    rm $out/lib/anytype/resources/app-update.yml

    substituteInPlace $out/share/applications/anytype.desktop \
      --replace-fail "Exec=/opt/Anytype/anytype --ozone-platform-hint=auto %U" "Exec=anytype %U"

    makeWrapper $out/lib/anytype/anytype $out/bin/anytype \
      --prefix PATH : ${lib.makeBinPath [ lsof ]} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}"

    # Browser web-clipper helper (static Go binary) needs lsof on PATH.
    wrapProgram $out/lib/anytype/resources/app.asar.unpacked/dist/nativeMessagingHost \
      --prefix PATH : ${lib.makeBinPath [ lsof ]}

    runHook postInstall
  '';

  meta = {
    description = "P2P note-taking tool (official prebuilt package)";
    homepage = "https://anytype.io/";
    changelog = "https://github.com/anyproto/anytype-ts/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.unfreeRedistributable;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "anytype";
    platforms = [ "x86_64-linux" ];
  };
})
