{ pkgs, ... }:
{
  users.defaultUserShell = pkgs.zsh;

  users.users = {
    cschmitt = {
      description = "Christopher Schmitt";
      shell = pkgs.zsh;
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
      isNormalUser = true;
      home = "/home/cschmitt";
      openssh.authorizedKeys.keys = [
      ];
    };
    root = {
      shell = pkgs.bashInteractive;
    };
  };

  security.sudo.extraRules = [
    {
      users = [ "cschmitt" ];
      commands = [
        {
          command = "${pkgs.systemd}/bin/systemctl suspend";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.systemd}/bin/reboot";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.systemd}/bin/poweroff";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/nixos-rebuild";
          options = [
            "SETENV"
            "NOPASSWD"
          ];
        }
      ];
    }
  ];

}
