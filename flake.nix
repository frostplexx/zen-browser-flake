{
  description = "Zen Browser";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };
  outputs = { self, nixpkgs }:
    let
      # Previous code unchanged until installPhase...
      mkZen = system: { variant ? null }: 
        let
          pkgs = import nixpkgs { inherit system; };
          downloadData = 
            if system == "x86_64-linux" 
            then downloadUrl.${system}.${variant}
            else downloadUrl.${system};
          
          # Rest of the let bindings unchanged...

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
            
            # Set proper permissions
            chmod -R 755 "$out/Applications/Zen Browser.app"
            
            # Remove quarantine attribute if it exists
            ${pkgs.xattr}/bin/xattr -rd com.apple.quarantine "$out/Applications/Zen Browser.app" || true
            
            # Ensure proper ownership
            chown -R $(whoami) "$out/Applications/Zen Browser.app"
            
            # Create symlink in bin
            ln -s "$out/Applications/Zen Browser.app/Contents/MacOS/zen" $out/bin/zen
            
            # Clean up
            rm -rf $tmp_dir
          '';

          fixupPhase = if system == "x86_64-linux" then ''
            # Linux fixup phase unchanged...
          '' else ''
            chmod +x "$out/Applications/Zen Browser.app/Contents/MacOS/"*
            
            # Ensure binary is executable
            chmod +x "$out/Applications/Zen Browser.app/Contents/MacOS/zen"
            
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
            nativeBuildInputs = with pkgs; [ makeWrapper xattr ] 
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
