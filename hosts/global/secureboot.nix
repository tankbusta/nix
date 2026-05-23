{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.boot.secureboot;
in
{
  imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

  options.boot.secureboot = {
    enable = lib.mkEnableOption "SecureBoot via lanzaboote (replaces systemd-boot)";

    pkiBundle = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sbctl";
      description = "Path to the sbctl PKI bundle used to sign boot artifacts.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.loader.systemd-boot.enable = lib.mkForce false;

    boot.lanzaboote = {
      enable = true;
      pkiBundle = cfg.pkiBundle;
    };

    environment.systemPackages = [ pkgs.sbctl ];
  };
}
