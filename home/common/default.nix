{ config, pkgs, ... }:

{
  # Import common home-manager modules
  imports = [
    ./shell.nix
  ];

  # Common packages across all hosts
  home.packages = with pkgs; [
    curl
    wget
    htop
    tree
    ripgrep
    fd
    jq
    lshw
    usbutils
  ];

  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;

  # SSH with 1Password agent
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks."*" = {
      extraOptions = {
        IdentityAgent = "~/.1password/agent.sock";
      };
    };
  };
}
