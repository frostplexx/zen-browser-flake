{
  name,
  variant,
  desktopFile,
  policies ? {},
  lib,
  stdenv,
  config,
  wrapGAppsHook3,
  autoPatchelfHook,
  alsa-lib,
  curl,
  dbus-glib,
  gtk3,
  libXtst,
  libva,
  libGL,
  pciutils,
  pipewire,
  adwaita-icon-theme,
  libva-vdpau-driver,
  writeText,
  patchelfUnstable, # have to use patchelfUnstable to support --no-clobber-old-sections
  # macOS specific inputs
  undmg,
  makeWrapper,
  applicationName ?
    "Zen"
    + (
      if stdenv.isLinux
      then "Browser"
      else ""
    )
    + (
      if stdenv.isLinux
      then
        (
          if name == "beta"
          then " (Beta)"
          else if name == "twilight"
          then " (Twilight)"
          else if name == "twilight-official"
          then " (Twilight)"
          else ""
        )
      else ""
    ),
}: let
  binaryName = if stdenv.isLinux then "zen-${name}" else "zen";

  libName = "zen-bin-${variant.version}";

  mozillaPlatforms = {
    x86_64-linux = "linux-x86_64";
    aarch64-linux = "linux-aarch64";
    x86_64-darwin = "macos-universal";
    aarch64-darwin = "macos-universal";
  };

  firefoxPolicies =
    (config.firefox.policies or {})
    // policies;

  policiesJson = writeText "firefox-policies.json" (builtins.toJSON {policies = firefoxPolicies;});

  pname = "zen-${name}-bin-unwrapped";

  isLinux = stdenv.isLinux;
  isDarwin = stdenv.isDarwin;
in
  stdenv.mkDerivation {
    inherit pname;
    inherit (variant) version;

    src =
      if isDarwin
      then builtins.fetchurl {inherit (variant) url sha256;}
      else builtins.fetchTarball {inherit (variant) url sha256;};

    desktopSrc = ./assets/desktop;

    nativeBuildInputs =
      if isDarwin
      then [undmg makeWrapper]
      else [
        wrapGAppsHook3
        autoPatchelfHook
        patchelfUnstable
      ];

    buildInputs = lib.optionals isLinux [
      gtk3
      adwaita-icon-theme
      alsa-lib
      dbus-glib
      libXtst
    ];

    runtimeDependencies = lib.optionals isLinux [
      curl
      libva.out
      pciutils
      libGL
      libva-vdpau-driver
    ];

    appendRunpaths = lib.optionals isLinux [
      "${libGL}/lib"
      "${pipewire}/lib"
    ];

    # Firefox uses "relrhack" to manually process relocations from a fixed offset
    patchelfFlags = lib.optionals isLinux ["--no-clobber-old-sections"];

    unpackPhase = lib.optionalString isDarwin ''
      runHook preUnpack

      undmg $src
      # Find the .app directory and move it to the expected location
      # find . -name "*.app" -type d -exec mv {} "Zen.app" \;

      runHook postUnpack
    '';

    preFixup = lib.optionalString isLinux ''
      gappsWrapperArgs+=(
        --add-flags '--name "''${MOZ_APP_LAUNCHER:-${binaryName}}"'
      )
    '';

    installPhase =
      if isDarwin
      then ''
        mkdir -p "$out/Applications"
        cp -r "Zen.app" "$out/Applications/"

        mkdir -p "$out/bin"
        makeWrapper "$out/Applications/Zen.app/Contents/MacOS/zen" "$out/bin/${binaryName}" \
          --set MOZ_APP_LAUNCHER "${binaryName}"
        # ln -s "$out/bin/${binaryName}" "$out/bin/zen"

        # Install policies for macOS
        mkdir -p "$out/Applications/Zen.app/Contents/Resources/distribution"
        ln -s ${policiesJson} "$out/Applications/Zen.app/Contents/Resources/distribution/policies.json"
      ''
      else ''
        mkdir -p "$prefix/lib/${libName}"
        cp -r "$src"/* "$prefix/lib/${libName}"

        mkdir -p "$out/bin"
        ln -s "$prefix/lib/${libName}/zen" "$out/bin/${binaryName}"
        # ! twilight and beta could collide if both are installed
        ln -s "$out/bin/${binaryName}" "$out/bin/zen"

        install -D $desktopSrc/${desktopFile} $out/share/applications/${desktopFile}

        mkdir -p "$out/lib/${libName}/distribution"
        ln -s ${policiesJson} "$out/lib/${libName}/distribution/policies.json"

        install -D $src/browser/chrome/icons/default/default16.png $out/share/icons/hicolor/16x16/apps/zen-${name}.png
        install -D $src/browser/chrome/icons/default/default32.png $out/share/icons/hicolor/32x32/apps/zen-${name}.png
        install -D $src/browser/chrome/icons/default/default48.png $out/share/icons/hicolor/48x48/apps/zen-${name}.png
        install -D $src/browser/chrome/icons/default/default64.png $out/share/icons/hicolor/64x64/apps/zen-${name}.png
        install -D $src/browser/chrome/icons/default/default128.png $out/share/icons/hicolor/128x128/apps/zen-${name}.png
      '';

    passthru =
      {
        inherit applicationName binaryName libName;
        ffmpegSupport = true;
        gssSupport = true;
      }
      // lib.optionalAttrs isLinux {
        gtk3 = gtk3;
      };

    meta = {
      inherit desktopFile;
      description = "Experience tranquillity while browsing the web without people tracking you!";
      homepage = "https://zen-browser.app";
      downloadPage = "https://zen-browser.app/download/";
      changelog = "https://github.com/zen-browser/desktop/releases";
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      platforms = builtins.attrNames mozillaPlatforms;
      hydraPlatforms = [];
      mainProgram = binaryName;
    };
  }
