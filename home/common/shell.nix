{ config, pkgs, ... }:

{
  # Zsh shell configuration
  programs.zsh = {
    enable = true;

    shellAliases = {
      ll = "ls -lh";
      la = "ls -lah";
      ".." = "cd ..";
      "..." = "cd ../..";
      grep = "grep --color=auto";
    };

    initContent = ''
      # Custom zsh configuration
      export EDITOR=vim
    '';

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "sudo" ];
      theme = "robbyrussell";
    };
  };

  # Bash configuration (fallback)
  programs.bash = {
    enable = true;

    shellAliases = {
      ll = "ls -lh";
      la = "ls -lah";
      ".." = "cd ..";
      grep = "grep --color=auto";
    };

    bashrcExtra = ''
      # Custom bash configuration
      export EDITOR=vim
    '';
  };

}
