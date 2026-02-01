{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "daedalus";

  # Bootloader - adjust based on your system
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking.networkmanager.enable = true;

  # Timezone
  time.timeZone = "America/Denver";

  # Host-specific packages
  environment.systemPackages = with pkgs; [
    vim
    wget
  ];

  system.stateVersion = "25.11";
}
