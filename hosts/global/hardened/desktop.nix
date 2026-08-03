{ config, lib, pkgs, ... }:

let
  cfg = config.my.hardened;
in
{
  config = lib.mkIf (cfg.enable && cfg.desktop.enable) {
    hardware.bluetooth.enable = lib.mkIf cfg.desktop.disableBluetooth (lib.mkForce false);
    boot.blacklistedKernelModules = lib.mkIf cfg.desktop.disableBluetooth [
      "bluetooth"
      "btusb"
      "btintel"
      "btrtl"
      "btbcm"
      "btmtk"
    ];

    # Password only
    services.fprintd.enable = lib.mkIf cfg.desktop.disableFingerprint (lib.mkForce false);

    services.logind.settings.Login = {
      IdleAction = "lock";
      IdleActionSec = cfg.desktop.idleLockSeconds;
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "suspend";
      HandleLidSwitchDocked = "suspend";
    };

    nix.settings.substituters = lib.mkForce [ ];
    nix.settings.trusted-substituters = lib.mkForce [ ];
    nix.gc.automatic = lib.mkForce false;
  };
}
