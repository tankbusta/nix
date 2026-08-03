{ config, lib, pkgs, ... }:

let
  cfg = config.my.hardened;
in
{
  config = lib.mkIf (cfg.enable && cfg.usb.enable) {
    services.usbguard = {
      enable = true;
      dbus.enable = true;

      implicitPolicyTarget = "block";
      presentDevicePolicy = "keep";
      presentControllerPolicy = "keep";
      insertedDevicePolicy = "block";
      restoreControllerDeviceState = false;

      IPCAllowedUsers = cfg.usb.ipcAllowedUsers;

      # Declarative (and therefore immutable) policy. Only hubs are allowed
      # implicitly, so the USB tree itself comes up; everything else falls
      # through to ImplicitPolicyTarget=block.
      #
      # To use a device on purpose:
      #   usbguard list-devices
      #   usbguard allow-device <id>
      rules = ''
        allow with-interface equals { 09:00:* }
      '';
    };

    environment.systemPackages = [ pkgs.usbguard ];

    # Even for a device you deliberately allow, do not let the desktop mount it
    # on sight -- automatic filesystem probing is its own attack surface.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{UDISKS_AUTO}="0", ENV{UDISKS_IGNORE}="1"
    '';

    # DMA-capable ports are a different problem from USB enumeration: they let
    # hardware read RAM directly, no driver required.
    boot.blacklistedKernelModules = lib.mkIf cfg.usb.blockDma [
      "firewire-core"
      "firewire-ohci"
      "firewire-sbp2"
      "thunderbolt"
      "thunderbolt-net"
    ];

    boot.kernelParams = lib.mkIf cfg.usb.blockDma [
      "intel_iommu=on"
      "amd_iommu=on"
      "iommu=force"
      "iommu.strict=1"
      "iommu.passthrough=0"
      "efi=disable_early_pci_dma"
    ];
  };
}
