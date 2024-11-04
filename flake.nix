{
  description = "Zen Browser";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };
  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      version = "1.0.1-a.6";
      downloadUrl = {
        "x86_64-linux" = {
          specific = {
            url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.linux-specific.tar.bz2";
            sha256 = "sha256:0jkzdrsd1qdw3pwdafnl5xb061vryxzgwmvp1a6ghdwgl2dm2fcz";
          };
          generic = {
            url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.linux-generic.tar.bz2";
            sha256 = "sha256:17c1ayxjdn8c28c5xvj3f94zjyiiwn8fihm3nq440b9dhkg01qcz";
          };
        };
        "aarch64-darwin" = {
          url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.macos-aarch64.dmg";
          # You'll need to replace this with the actual SHA256 for the macOS ARM build
          sha256 = "sha256-Ob+R6g0/DNJ02On9XSreiVeJ+IMIKtGbHrd5qXxdOiM=";
        };
      };

      mkZen = system: { variant ? null }: 
        let
          pkgs = import nixpkgs { inherit system; };
          downloadData = 
            if system == "x86_64-linux" 
            then downloadUrl.${system}.${variant}
            else downloadUrl.${system};
          
          # System-specific runtime libraries
          runtimeLibs = with pkgs; 
            if system == "x86_64-linux" then [
              libGL libGLU libevent libffi libjpeg libpng libstartup_notification libvpx libwebp
              stdenv.cc.cc fontconfig libxkbcommon zlib freetype
              gtk3 libxml2 dbus xcb-util-cursor alsa-lib libpulseaudio pango atk cairo gdk-pixbuf glib
              udev libva mesa libnotify cups pciutils
              ffmpeg libglvnd pipewire
            ] ++ (with pkgs.xorg; [
              libxcb libX11 libXcursor libXrandr libXi libXext libXcomposite libXdamage
              libXfixes libXScrnSaver
            ])
            else if system == "aarch64-darwin" then [
              stdenv.cc.cc
              libiconv
              darwin.apple_sdk.frameworks.AppKit
              darwin.apple_sdk.frameworks.Foundation
              darwin.apple_sdk.frameworks.CoreServices
              darwin.apple_sdk.frameworks.CoreFoundation
              darwin.apple_sdk.frameworks.Security
              darwin.apple_sdk.frameworks.CoreAudio
              darwin.apple_sdk.frameworks.AudioToolbox
              darwin.apple_sdk.frameworks.CoreMedia
              darwin.apple_sdk.frameworks.AVFoundation
              darwin.apple_sdk.frameworks.MediaToolbox
              darwin.apple_sdk.frameworks.VideoToolbox
            ] else [];

          # System-specific source fetching
          fetchSource = if system == "x86_64-linux" then
            builtins.fetchTarball {
              inherit (downloadData) url sha256;
            }
          else if system == "aarch64-darwin" then
            pkgs.fetchurl {
              inherit (downloadData) url sha256;
            }
          else null;

installPhase = if system == "x86_64-linux" then ''
            mkdir -p $out/bin && cp -r $src/* $out/bin
            install -D $desktopSrc/zen.desktop $out/share/applications/zen.desktop
            install -D $src/browser/chrome/icons/default/default128.png $out/share/icons/hicolor/128x128/apps/zen.png
          '' else ''
            # Create a temporary directory for DMG extraction
            tmp_dir=$(mktemp -d)
            
            # Extract DMG contents
            ${pkgs.undmg}/bin/undmg $src
            
            # Create target directories
            mkdir -p $out/Applications
            mkdir -p $out/bin
            
            # Copy the extracted .app bundle
            cp -r "Zen Browser.app" $out/Applications/
            
            # Create symlink in bin
            ln -s "$out/Applications/Zen Browser.app/Contents/MacOS/zen" $out/bin/zen
            
            # Clean up
            rm -rf $tmp_dir
          '';

          fixupPhase = if system == "x86_64-linux" then ''
            chmod 755 $out/bin/*
            patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $out/bin/zen
            wrapProgram $out/bin/zen --set LD_LIBRARY_PATH "${pkgs.lib.makeLibraryPath runtimeLibs}" \
                      --set MOZ_LEGACY_PROFILES 1 --set MOZ_ALLOW_DOWNGRADE 1 --set MOZ_APP_LAUNCHER zen --prefix XDG_DATA_DIRS : "$GSETTINGS_SCHEMAS_PATH"
            patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $out/bin/zen-bin
            wrapProgram $out/bin/zen-bin --set LD_LIBRARY_PATH "${pkgs.lib.makeLibraryPath runtimeLibs}" \
                      --set MOZ_LEGACY_PROFILES 1 --set MOZ_ALLOW_DOWNGRADE 1 --set MOZ_APP_LAUNCHER zen --prefix XDG_DATA_DIRS : "$GSETTINGS_SCHEMAS_PATH"
            patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $out/bin/glxtest
            wrapProgram $out/bin/glxtest --set LD_LIBRARY_PATH "${pkgs.lib.makeLibraryPath runtimeLibs}"
            patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $out/bin/updater
            wrapProgram $out/bin/updater --set LD_LIBRARY_PATH "${pkgs.lib.makeLibraryPath runtimeLibs}"
            patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $out/bin/vaapitest
            wrapProgram $out/bin/vaapitest --set LD_LIBRARY_PATH "${pkgs.lib.makeLibraryPath runtimeLibs}"
          '' else ''
            chmod +x "$out/Applications/Zen Browser.app/Contents/MacOS/"*
            xattr -rd com.apple.quarantine "$out/Applications/Zen Browser.app"
            chmod -R 755 "$out/Applications/Zen Browser.app"
            wrapProgram "$out/Applications/Zen Browser.app/Contents/MacOS/zen" \
              --set DYLD_LIBRARY_PATH "${pkgs.lib.makeLibraryPath runtimeLibs}" \
              --set MOZ_LEGACY_PROFILES 1 \
              --set MOZ_ALLOW_DOWNGRADE 1
          '';
        in
          pkgs.stdenv.mkDerivation {
            inherit version;
            pname = "zen-browser";
            
            src = fetchSource;
            
            desktopSrc = ./.;
            phases = [ "installPhase" "fixupPhase" ];
            nativeBuildInputs = with pkgs; [ makeWrapper ] 
              ++ (if system == "x86_64-linux" then [ copyDesktopItems wrapGAppsHook ] else [ undmg ]);
            
            inherit installPhase fixupPhase;
            
            meta = {
              mainProgram = "zen";
              platforms = [ system ];
            };
          };
    in
    {
      packages = forAllSystems (system: 
        if system == "x86_64-linux" then {
          generic = mkZen system { variant = "generic"; };
          specific = mkZen system { variant = "specific"; };
          default = self.packages.${system}.specific;
        } else {
          default = mkZen system {};
        }
      );
    };
}
