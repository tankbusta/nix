{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "odyssey";

  # Bootloader - adjust based on your system
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # SecureBoot via lanzaboote. Requires manual sbctl key generation and
  # firmware setup-mode enrollment before this will boot. See:
  # https://github.com/nix-community/lanzaboote/blob/master/docs/getting-started/prepare-your-system.md
  boot.secureboot.enable = true;

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

  # Hostile-network
  my.hardened = {
    specialisation.enable = true;

    # Also drives the desktop widget's home icon, not just auto-arming.
    trustedNetworks = [ "Panic At The Cisco" ];

    autoArm.enable = true;

    usb.ipcAllowedUsers = [
      "root"
      "cschmitt"
    ];

    # Set this to a Tailscale node at home to tunnel everything while hardened.
    # network.exitNode = "daedalus";
  };

  # Docker
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };
  users.users.cschmitt.extraGroups = [ "docker" ];
}
