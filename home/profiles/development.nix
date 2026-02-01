{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    vscode
    git
    gh
    gnumake
    nodejs
    python3
  ];

  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      ms-python.python
      jnoortheen.nix-ide
      anthropic.claude-code
    ];
  };

  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "Christopher Schmitt";
        email = "cschmitt@tankbusta.net";
      };

      init.defaultBranch = "main";
      pull.rebase = true;
      core.editor = "vim";

      alias = {
        st = "status";
        co = "checkout";
        br = "branch";
        ci = "commit";
        lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
      };
    };
  };
}
