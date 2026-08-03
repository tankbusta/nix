{ ... }:

{

  imports = [
    ./meta.nix
    ./users.nix
    ./programs.nix
    ./services.nix
    ./secureboot.nix
    ./hardened
  ];

}