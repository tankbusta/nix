{ config, pkgs, ... }:

{
  # Import common home-manager configuration
  imports = [
    ../../home/common
    ../../home/profiles/development.nix
    ../../home/profiles/reverse-engineering.nix
    ../../home/profiles/social.nix
    ../../home/modules/firefox
  ];

  home.username = "cschmitt";
  home.homeDirectory = "/home/cschmitt";

  home.stateVersion = "25.11";

  home.language = {
    time = "en_GB.UTF-8"; # 24 hour
  };

  # Host-specific packages for this user
  home.packages = with pkgs; [
    neofetch
    pkgs.claude-code
  ];
}
