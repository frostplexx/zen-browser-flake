{
  description = "Zen Browser";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    version = "1.0.2-b.1";
    downloadUrl = {
      specific = {
        "x86_64-linux" = {
          url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.linux-specific.tar.bz2";
          sha256 = "1bnalbpzk6alihjsvl9nmzn7zfy9a3dcil8dbrlbfz68jiz88hl1";
        };
        "aarch64-darwin" = {
          url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.macos-arm64.tar.bz2";
          sha256 = ""; # Replace with actual hash after downloading
        };
      };
      generic = {
        "x86_64-linux" = {
          url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.linux-generic.tar.bz2";
          sha256 = "1bjwcar919hp2drlnirfx8a7nhcglm4kwymknzqxdxxj7x8zi4zr";
        };
        "aarch64-darwin" = {
          url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.macos-universal.tar.bz2";
          sha256 = ""; # Replace with actual hash after downloading
        };
      };
    };

    mkZen = system: {variant}: let
      pkgs = import nixpkgs {
        inherit system;
      };
      
      downloadData = downloadUrl."${variant}"."${system}";
      
      runtimeLibs = with pkgs;
        if system == "aarch64-darwin" then [
          # macOS-specific libraries
          darwin.apple_sdk.frameworks.AppKit
          darwin.apple_sdk.frameworks.CoreFoundation
          darwin.apple_sdk.frameworks.CoreServices
          darwin.apple_sdk.frameworks.Foundation
          darwin.apple_sdk.frameworks.Security
          darwin.apple_sdk.frameworks.WebKit
          libiconv
        ] else with pkgs; [
          # Linux libraries (unchanged)
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

        src = builtins.fetchTarball {
          url = downloadData.url;
          sha256 = downloadData.sha256;
        };

        desktopSrc = ./.;

        phases = ["installPhase" "fixupPhase"];

        nativeBuildInputs = with pkgs; [
          makeWrapper
          copyDesktopItems
        ] ++ lib.optional (!pkgs.stdenv.isDarwin) wrapGAppsHook;

        installPhase = ''
          mkdir -p $out/{bin,opt/zen}
          cp -r $src/* $out/opt/zen
          ln -s $out/opt/zen/zen $out/bin/zen

          ${if pkgs.stdenv.isDarwin then "" else ''
            install -D $desktopSrc/zen.desktop $out/share/applications/zen.desktop

            install -D $src/browser/chrome/icons/default/default16.png $out/share/icons/hicolor/16x16/apps/zen.png
            install -D $src/browser/chrome/icons/default/default32.png $out/share/icons/hicolor/32x32/apps/zen.png
            install -D $src/browser/chrome/icons/default/default48.png $out/share/icons/hicolor/48x48/apps/zen.png
            install -D $src/browser/chrome/icons/default/default64.png $out/share/icons/hicolor/64x64/apps/zen.png
            install -D $src/browser/chrome/icons/default/default128.png $out/share/icons/hicolor/128x128/apps/zen.png
          ''}
        '';

        fixupPhase = if pkgs.stdenv.isDarwin then ''
          chmod 755 $out/bin/zen $out/opt/zen/*
          wrapProgram $out/opt/zen/zen \
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

          patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $out/opt/zen/glxtest
               wrapProgram $out/opt/zen/glxtest --set LD_LIBRARY_PATH "${pkgs.lib.makeLibraryPath runtimeLibs}"

          patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $out/opt/zen/updater
               wrapProgram $out/opt/zen/updater --set LD_LIBRARY_PATH "${pkgs.lib.makeLibraryPath runtimeLibs}"

          patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $out/opt/zen/vaapitest
               wrapProgram $out/opt/zen/vaapitest --set LD_LIBRARY_PATH "${pkgs.lib.makeLibraryPath runtimeLibs}"
        '';

        meta.mainProgram = "zen";
      };
  in {
    packages = forAllSystems (system: {
      generic = mkZen system {variant = "generic";};
      specific = mkZen system {variant = "specific";};
      default = self.packages.${system}.specific;
    });
  };
}
