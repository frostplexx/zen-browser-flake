{
  description = "Zen Browser";
  # Previous code unchanged until installPhase...

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
            wrapProgram "$out/Applications/Zen Browser.app/Contents/MacOS/zen" \
              --set DYLD_LIBRARY_PATH "${pkgs.lib.makeLibraryPath runtimeLibs}" \
              --set MOZ_LEGACY_PROFILES 1 \
              --set MOZ_ALLOW_DOWNGRADE 1
          '';

        in
          pkgs.stdenv.mkDerivation {
            inherit version;
            pname = "zen-browser";
            src = builtins.fetchTarball {
              url = downloadData.url;
              sha256 = downloadData.sha256;
            };
            
            desktopSrc = ./.;
            phases = [ "installPhase" "fixupPhase" ];
            nativeBuildInputs = with pkgs; [ makeWrapper ] 
              ++ (if system == "x86_64-linux" then [ copyDesktopItems wrapGAppsHook ] else []);
            
            inherit installPhase fixupPhase;
            
            meta = {
              mainProgram = "zen";
              platforms = [ system ];
            };
          };
    in
    {
      packages = forAllSystems (system: {
        generic = mkZen system { variant = "generic"; };
        specific = mkZen system { variant = "specific"; };
        default = self.packages.${system}.specific;
      });
    };
}
