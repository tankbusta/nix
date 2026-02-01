{ config, pkgs, ... }:

{
  # Import common home-manager configuration
  imports = [
    ../../home/common
    ../../home/profiles/development.nix
    ../../home/modules/firefox
  ];

  home.username = "cschmitt";
  home.homeDirectory = "/home/cschmitt";

  home.stateVersion = "25.11";

  # Host-specific packages for this user
  home.packages = with pkgs; [
    neofetch
    pkgs.claude-code
  ];
}
