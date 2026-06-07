{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    vscode
    git
    gh
    gnumake
    nodejs
    python3

    # Kubernetes
    kubectl
    krew
    kubelogin-oidc
    cilium-cli
    talosctl
    omnictl

    # Go
    go
    gopls
    delve
    go-tools
  ];

  home.sessionPath = [ "${config.home.homeDirectory}/.krew/bin" ];
  home.file.".kube/config".source = ./kube/lcars-prod.yaml;
  home.file.".talos/config".source = ./kube/lcars-prod-talosconfig.yaml;
  home.file.".config/omni/config".source = ./kube/omniconfig.yaml;

  programs.vscode = {
    enable = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      # ms-python.python  # temporarily disabled - jedi version conflict in nixpkgs
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
