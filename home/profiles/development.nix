{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    vscode
    git
    gh
    gnumake
    nodejs
    python3

    # Go
    go
    gopls
    delve
    go-tools
  ];

  programs.vscode = {
    enable = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      ms-python.python
      jnoortheen.nix-ide
      anthropic.claude-code
      golang.go
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
