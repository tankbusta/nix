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

  # Graphics
  hardware.graphics.enable = true;

  # NVIDIA
  services.xserver.videoDrivers = [
    "modesetting"
    "nvidia"
  ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  hardware.nvidia.prime = {
    offload = {
      enable = true;
      enableOffloadCmd = true;
    };

    intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:1:0:0";
	};

  # Host-specific packages
  environment.systemPackages = with pkgs; [
    vim
    wget
  ];

  system.stateVersion = "25.11";

  # Dell Fingerprint Reader
  services.fprintd.enable = true;
  services.fprintd.tod.driver = pkgs.libfprint-2-tod1-goodix;
}
