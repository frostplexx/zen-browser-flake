{
  description = "Zen Browser";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    version = "1.0.2-b.1";
    downloadUrl = {
      specific = {
        "x86_64-linux" = {
          url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.linux-specific.tar.bz2";
          sha256 = "1bnalbpzk6alihjsvl9nmzn7zfy9a3dcil8dbrlbfz68jiz88hl1";
        };
        "aarch64-linux" = {
          url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.linux-aarch64.tar.bz2";
          sha256 = "";
        };
        "aarch64-darwin" = {
          url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.macos-aarch64.dmg";
          sha256 = "IiMOO/6fq+w2gjAtItXNnmccjhaKkhyaEwaIPtVuOOM=";
        };
        "x86_64-darwin" = {
          url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.macos-x86_64.dmg";
          sha256 = "";
        };
      };
      generic = {
        "x86_64-linux" = {
          url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.linux-generic.tar.bz2";
          sha256 = "1bjwcar919hp2drlnirfx8a7nhcglm4kwymknzqxdxxj7x8zi4zr";
        };
        "aarch64-linux" = {
          url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.linux-aarch64.tar.bz2";
          sha256 = "";
        };
        "aarch64-darwin" = {
          url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.macos-aarch64.dmg";
          sha256 = "IiMOO/6fq+w2gjAtItXNnmccjhaKkhyaEwaIPtVuOOM=";
        };
        "x86_64-darwin" = {
          url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.macos-x86_64.dmg";
          sha256 = "";
        };
      };
    };

    mkZen = system: {variant}: let
      pkgs = import nixpkgs {
        inherit system;
      };
      
      downloadData = downloadUrl."${variant}"."${system}";
      
      runtimeLibs = with pkgs;
        if stdenv.isDarwin then [
          # macOS-specific libraries
          darwin.apple_sdk.frameworks.AppKit
          darwin.apple_sdk.frameworks.CoreFoundation
          darwin.apple_sdk.frameworks.CoreServices
          darwin.apple_sdk.frameworks.Foundation
          darwin.apple_sdk.frameworks.Security
          darwin.apple_sdk.frameworks.WebKit
          darwin.apple_sdk.frameworks.CoreAudio
          darwin.apple_sdk.frameworks.AudioUnit
          darwin.apple_sdk.frameworks.CoreMedia
          darwin.apple_sdk.frameworks.VideoToolbox
          libiconv
        ] else with pkgs; [
          # Linux libraries
          libGL
          libGLU
          libevent
          libffi
          libjpeg
          libpng
          libstartup_notification
          libvpx
          libwebp
          stdenv.cc.cc
          fontconfig
          libxkbcommon
          zlib
          freetype
          gtk3
          libxml2
          dbus
          xcb-util-cursor
          alsa-lib
          libpulseaudio
          pango
          atk
          cairo
          gdk-pixbuf
          glib
          udev
          libva
          mesa
          libnotify
          cups
          pciutils
          ffmpeg
          libglvnd
          pipewire
          speechd
        ] ++ (with pkgs.xorg; [
          libxcb
          libX11
          libXcursor
          libXrandr
          libXi
          libXext
          libXcomposite
          libXdamage
          libXfixes
          libXScrnSaver
        ]);
    in
      pkgs.stdenv.mkDerivation {
        inherit version;
        pname = "zen-browser";

        src = if pkgs.stdenv.isDarwin then
          pkgs.fetchurl {
            inherit (downloadData) url sha256;
          }
        else
          builtins.fetchTarball {
            inherit (downloadData) url sha256;
          };

        desktopSrc = ./.;

        nativeBuildInputs = with pkgs; [
          makeWrapper
          copyDesktopItems
        ] ++ lib.optionals (!stdenv.isDarwin) [ wrapGAppsHook ]
          ++ lib.optionals stdenv.isDarwin [ undmg ];

        sourceRoot = if pkgs.stdenv.isDarwin then "Zen Browser.app" else ".";
        
        phases = if pkgs.stdenv.isDarwin then [
          "unpackPhase"
          "installPhase"
          "fixupPhase"
        ] else [
          "installPhase"
          "fixupPhase"
        ];

        installPhase = if pkgs.stdenv.isDarwin then ''
          mkdir -p $out/Applications/
          cp -r . "$out/Applications/Zen Browser.app"
          mkdir -p $out/bin
          ln -s "$out/Applications/Zen Browser.app/Contents/MacOS/zen" $out/bin/zen
        '' else ''
          mkdir -p $out/{bin,opt/zen}
          cp -r $src/* $out/opt/zen
          ln -s $out/opt/zen/zen $out/bin/zen

          install -D $desktopSrc/zen.desktop $out/share/applications/zen.desktop

          install -D $src/browser/chrome/icons/default/default16.png $out/share/icons/hicolor/16x16/apps/zen.png
          install -D $src/browser/chrome/icons/default/default32.png $out/share/icons/hicolor/32x32/apps/zen.png
          install -D $src/browser/chrome/icons/default/default48.png $out/share/icons/hicolor/48x48/apps/zen.png
          install -D $src/browser/chrome/icons/default/default64.png $out/share/icons/hicolor/64x64/apps/zen.png
          install -D $src/browser/chrome/icons/default/default128.png $out/share/icons/hicolor/128x128/apps/zen.png
        '';

        fixupPhase = if pkgs.stdenv.isDarwin then ''
          mkdir -p $out/bin
          makeWrapper "$out/Applications/Zen Browser.app/Contents/MacOS/zen" $out/bin/zen \
            --set DYLD_LIBRARY_PATH "${pkgs.lib.makeLibraryPath runtimeLibs}" \
            --set MOZ_LEGACY_PROFILES 1 \
            --set MOZ_ALLOW_DOWNGRADE 1 \
            --set MOZ_APP_LAUNCHER zen
        '' else ''
          chmod 755 $out/bin/zen $out/opt/zen/*

          patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $out/opt/zen/zen
          wrapProgram $out/opt/zen/zen --set LD_LIBRARY_PATH "${pkgs.lib.makeLibraryPath runtimeLibs}" \
                               --set MOZ_LEGACY_PROFILES 1 --set MOZ_ALLOW_DOWNGRADE 1 --set MOZ_APP_LAUNCHER zen --prefix XDG_DATA_DIRS : "$GSETTINGS_SCHEMAS_PATH"

          patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $out/opt/zen/zen-bin
          wrapProgram $out/opt/zen/zen-bin --set LD_LIBRARY_PATH "${pkgs.lib.makeLibraryPath runtimeLibs}" \
                               --set MOZ_LEGACY_PROFILES 1 --set MOZ_ALLOW_DOWNGRADE 1 --set MOZ_APP_LAUNCHER zen --prefix XDG_DATA_DIRS : "$GSETTINGS_SCHEMAS_PATH"

          for binary in glxtest updater vaapitest; do
            if [ -f "$out/opt/zen/$binary" ]; then
              patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$out/opt/zen/$binary"
              wrapProgram "$out/opt/zen/$binary" --set LD_LIBRARY_PATH "${pkgs.lib.makeLibraryPath runtimeLibs}"
            fi
          done
        '';

        meta = {
          mainProgram = "zen";
          platforms = supportedSystems;
        };
      };
  in {
    packages = forAllSystems (system: {
      generic = mkZen system {variant = "generic";};
      specific = mkZen system {variant = "specific";};
      default = self.packages.${system}.specific;
    });
  };
}
