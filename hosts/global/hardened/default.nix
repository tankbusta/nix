{ config, lib, pkgs, ... }:

let
  cfg = config.my.hardened;

  # `switch-to-configuration` for the hardened specialisation. This path only
  # exists while the *parent* configuration is active -- specialisations do not
  # nest, so from inside hardened mode there is no `specialisation/` directory.
  hardenedSwitch = "/run/current-system/specialisation/${cfg.specialisation.name}/bin/switch-to-configuration";

  # The system profile always points at the parent (non-hardened) generation,
  # even from inside the specialisation. That is what makes disarming possible
  # without a rebuild -- important, because you do not want to be running
  # `nixos-rebuild` over conference wifi.
  parentSwitch = "/nix/var/nix/profiles/system/bin/switch-to-configuration";

  # Presence of this file is the single source of truth for "am I hardened?".
  # It is an `environment.etc` entry, so activation creates and removes it in
  # lockstep with the rest of the switch.
  marker = "/etc/hardened-mode";

  tailscaleBin = "${config.services.tailscale.package}/bin/tailscale";

  trusted = lib.concatMapStringsSep " " lib.escapeShellArg cfg.trustedNetworks;

  # One word on stdout, for anything that wants to render the state rather than
  # read a report. Keeping the logic here instead of in QML means it is testable
  # from a shell and the widget stays dumb.
  indicatorState = pkgs.writeShellScriptBin "hardened-indicator-state" ''
    # Is any name we are currently connected under in the trusted list? Checks
    # both NetworkManager connection names (which covers ethernet profiles) and
    # the live SSID off each wireless interface. Unlike the dispatcher this is
    # not running inside a NetworkManager hook, so nmcli is safe to call here.
    on_trusted_network() {
      names=$(${pkgs.networkmanager}/bin/nmcli -t -f NAME connection show --active 2>/dev/null)

      for w in /sys/class/net/*/wireless; do
        [ -e "$w" ] || continue
        dev=$(${pkgs.coreutils}/bin/basename "$(${pkgs.coreutils}/bin/dirname "$w")")
        s=$(${pkgs.iw}/bin/iw dev "$dev" link 2>/dev/null \
          | ${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*SSID: //p')
        # No indentation on the continuation line: these are compared with
        # `grep -qxF`, so a leading space would stop every SSID from matching.
        [ -n "$s" ] && names="$names
$s"
      done

      for t in ${trusted}; do
        printf '%s\n' "$names" | ${pkgs.gnugrep}/bin/grep -qxF "$t" && return 0
      done
      return 1
    }

    if [ -e ${marker} ]; then
      if ${pkgs.gnugrep}/bin/grep -q 'iommu.strict=1' /proc/cmdline; then
        echo full
      else
        echo runtime
      fi
    elif on_trusted_network; then
      echo home
    else
      echo off
    fi
  '';

  # Installed in *both* configurations. If the widget only existed in the
  # hardened one, switching would yank it out from under plasmashell and the
  # panel would show a broken-applet placeholder instead of a status.
  plasmoid = pkgs.runCommand "plasma-hardened-indicator" { } ''
    dir=$out/share/plasma/plasmoids/net.tankbusta.hardened
    mkdir -p "$dir/contents/ui"
    cp ${./plasmoid/metadata.json} "$dir/metadata.json"
    substitute ${./plasmoid/main.qml} "$dir/contents/ui/main.qml" \
      --replace-fail '@stateCommand@' '${indicatorState}/bin/hardened-indicator-state'
  '';

  # Reports what is actually in effect right now, by inspecting the running
  # system rather than by restating what the config asked for. The two must be
  # able to disagree -- that is the entire point of checking.
  #
  # No `set -e` here: every probe is best-effort, and a missing tool or an
  # inactive unit is information to print, not a reason to abort the report.
  hardenedStatus = pkgs.writeShellScriptBin "hardened-status" ''
    row()  { printf '  %-18s %s\n' "$1" "$2"; }
    unit() { ${pkgs.systemd}/bin/systemctl is-active "$1" 2>/dev/null || true; }

    nmconf=/etc/NetworkManager/NetworkManager.conf
    nmval() {
      v=$(${pkgs.gnugrep}/bin/grep -E "^$1=" "$nmconf" 2>/dev/null | ${pkgs.coreutils}/bin/cut -d= -f2-)
      if [ -n "$v" ]; then echo "$v"; else echo "(unset)"; fi
    }

    if [ -e ${marker} ]; then
      echo "mode        HARDENED"
    else
      echo "mode        normal"
    fi
    echo "generation  $(${pkgs.coreutils}/bin/readlink -f /run/current-system)"

    # A runtime switch cannot change kernel parameters -- those only take effect
    # by booting the hardened entry. Distinguishing the two tiers matters: it is
    # the difference between "usbguard is running" and "DMA is actually walled
    # off", and it is exactly the thing you would otherwise assume wrongly.
    if ${pkgs.gnugrep}/bin/grep -q 'iommu.strict=1' /proc/cmdline; then
      echo "boot tier   hardened kernel is booted"
    else
      echo "boot tier   normal kernel -- reboot into '${cfg.specialisation.name}' for IOMMU,"
      echo "            module blacklists and SMT settings"
    fi

    echo ""
    echo "services"
    row "usbguard"  "$(unit usbguard.service)"
    row "firewall"  "$(unit firewall.service)"
    row "resolved"  "$(unit systemd-resolved.service)"
    row "bluetooth" "$(unit bluetooth.service)"
    row "fprintd"   "$(unit fprintd.service)"
    row "docker"    "$(unit docker.service)"

    if [ "$(unit usbguard.service)" = "active" ]; then
      row "usb blocked" "$(${pkgs.usbguard}/bin/usbguard list-devices -b 2>/dev/null \
        | ${pkgs.coreutils}/bin/wc -l) device(s)"
    fi

    echo ""
    echo "network"
    for dev in $(${pkgs.networkmanager}/bin/nmcli -t -f DEVICE,TYPE device 2>/dev/null \
      | ${pkgs.gawk}/bin/awk -F: '$2=="wifi" || $2=="ethernet" {print $1}'); do
      row "$dev" "$(${pkgs.coreutils}/bin/cat /sys/class/net/"$dev"/address 2>/dev/null)"
    done
    row "mac policy"  "$(nmval 'wifi.cloned-mac-address')"
    row "autoconnect" "$(nmval 'connection.autoconnect')"
    row "mdns"        "$(nmval 'connection.mdns')"

    if [ -x ${tailscaleBin} ]; then
      exitnode=$(${tailscaleBin} debug prefs 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -oE '"ExitNodeID": *"[^"]*"' \
        | ${pkgs.coreutils}/bin/cut -d'"' -f4)
      if [ -n "$exitnode" ]; then
        row "exit node" "$exitnode"
      else
        row "exit node" "none"
      fi
    fi

    echo ""
    echo "dns"
    if [ "$(unit systemd-resolved.service)" = "active" ]; then
      ${pkgs.systemd}/bin/resolvectl status 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -E 'Protocols|Current DNS Server|DNS Servers' \
        | ${pkgs.gnused}/bin/sed 's/^ */  /' || true
    else
      row "resolver" "not systemd-resolved -- DNS is whatever the network handed us"
    fi
  '';

  unharden = pkgs.writeShellScriptBin "unharden" ''
    set -eu
    if [ ! -e ${marker} ]; then
      echo "not in hardened mode."
      exit 0
    fi
    echo "disarming hardened mode..."
    ${lib.optionalString (cfg.network.exitNode != null) ''
      sudo ${tailscaleBin} set --exit-node= || true
    ''}
    sudo ${parentSwitch} switch
    # Same reason as in `harden`: make Tailscale re-read the system resolver
    # rather than keep pointing resolv.conf at an upstream that just changed.
    sudo ${pkgs.systemd}/bin/systemctl try-restart tailscaled.service || true
  '';

  arm = pkgs.writeShellScript "harden-arm" ''
    set -eu
    if [ -e ${marker} ]; then
      echo "already in hardened mode."
      exit 0
    fi
    if [ ! -x ${hardenedSwitch} ]; then
      echo "no hardened specialisation in this generation -- rebuild first." >&2
      exit 1
    fi
    echo "arming hardened mode..."
    sudo ${hardenedSwitch} switch
    # Tailscale caches what it thinks the system resolver looks like. Crossing
    # a switch changes that (ignore-auto-dns, resolver list), and a stale view
    # leaves it forwarding to an upstream that is no longer there.
    sudo ${pkgs.systemd}/bin/systemctl try-restart tailscaled.service || true
    echo ""
    echo "hardened. note that kernel-level hardening (IOMMU, module blacklists,"
    echo "SMT) only applies after booting the '${cfg.specialisation.name}' entry."
  '';

  harden = pkgs.writeShellScriptBin "harden" ''
    set -eu
    case "''${1:-on}" in
      on | arm)
        exec ${arm}
        ;;
      off | disarm)
        exec ${unharden}/bin/unharden
        ;;
      status)
        exec ${hardenedStatus}/bin/hardened-status
        ;;
      *)
        echo "usage: harden [on|off|status]" >&2
        exit 1
        ;;
    esac
  '';
in
{
  imports = [
    ./network.nix
    ./usb.nix
    ./kernel.nix
    ./desktop.nix
    ./autoarm.nix
  ];

  options.my.hardened = {
    enable = lib.mkEnableOption ''
      hostile-network hardening. Do not set this directly on a host -- it marks
      *this* configuration as the hardened one. Use
      `my.hardened.specialisation.enable` to give a host a hardened variant
    '';

    specialisation = {
      enable = lib.mkEnableOption ''
        building a hardened specialisation of this host. Both the normal and
        hardened systems end up in one closure, so switching between them needs
        no network access and no rebuild
      '';

      name = lib.mkOption {
        type = lib.types.str;
        default = "hardened";
        description = "Specialisation name, also used as the boot entry tag.";
      };
    };

    # Lives at the top level rather than under `autoArm` because two things
    # consume it now: the dispatcher decides whether to arm, and the widget
    # decides whether to show the home icon.
    trustedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "home-5g" "Home Wired" ];
      description = ''
        NetworkManager connection names or SSIDs treated as home. These do not
        trigger auto-arming, and the desktop widget shows a home icon while
        connected to one.
      '';
    };

    autoArm = {
      enable = lib.mkEnableOption ''
        automatically arming hardened mode when joining a network that is not
        in `trustedNetworks`. This only ever escalates -- disarming is always
        manual, so a spoofed SSID cannot relax the machine
      '';

      notify = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Send a desktop notification when auto-arming fires.";
      };

      cooldownSeconds = lib.mkOption {
        type = lib.types.int;
        default = 90;
        description = ''
          How long after a configuration switch to ignore network events.
          Switching restarts NetworkManager, which emits a fresh "up" almost
          immediately; without this, `unharden` would be undone by the
          dispatcher it just woke up.
        '';
      };
    };

    network = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Network lockdown: firewall, MAC randomisation, no discovery chatter, DNS.";
      };

      disableWifiAutoconnect = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Stop NetworkManager from silently re-associating with saved SSIDs.
          This is the anti-KARMA control: in hardened mode you pick the network
          by hand every time.
        '';
      };

      ignoreDhcpDns = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Ignore DNS servers handed out by DHCP and use `dns` instead, so the
          venue cannot see or tamper with your lookups. Breaks captive portals
          until you run `hardened-dns portal`.
        '';
      };

      dns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "9.9.9.9#dns.quad9.net"
          "149.112.112.112#dns.quad9.net"
          "2620:fe::fe#dns.quad9.net"
        ];
        description = "Resolvers to use in hardened mode. Hostnames are required for strict DoT.";
      };

      dnsOverTls = lib.mkOption {
        type = lib.types.enum [ "true" "false" "opportunistic" ];
        default = "true";
        description = ''
          systemd-resolved DNSOverTLS mode. "true" is strict and will fail
          closed rather than fall back to plaintext.
        '';
      };

      exitNode = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "home-router";
        description = ''
          Tailscale node to force all traffic through while hardened. This is
          the strongest single control at a hostile venue -- everything leaves
          the laptop inside WireGuard. `unharden` clears it again.
        '';
      };
    };

    usb = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "USB and DMA lockdown via usbguard plus port/module blacklists.";
      };

      ipcAllowedUsers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "root" ];
        example = [ "root" "cschmitt" ];
        description = ''
          Users allowed to talk to usbguard, i.e. to run `usbguard list-devices`
          and `usbguard allow-device` without sudo when you deliberately want to
          plug something in.
        '';
      };

      blockDma = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Blacklist FireWire and Thunderbolt drivers and force strict IOMMU.
          Kills Thunderspy-style DMA attacks -- and also Thunderbolt docks.
        '';
      };
    };

    kernel = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Kernel sysctl and boot-parameter hardening.";
      };

      ptraceScope = lib.mkOption {
        type = lib.types.enum [ 0 1 2 3 ];
        default = 1;
        description = ''
          yama ptrace_scope. 1 (parent-only) still lets gdb/IDA debug processes
          they launch themselves; 2 requires CAP_SYS_PTRACE for everything and
          will get in the way of live analysis work.
        '';
      };

      lockModules = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Disallow loading kernel modules after boot. Off by default: it breaks
          anything that autoloads a module later (docker networking, tun, USB
          drivers for devices you plug in afterwards).
        '';
      };

      lockdown = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "integrity" "confidentiality" ]);
        default = null;
        description = ''
          Kernel lockdown LSM mode. Requires Secure Boot to mean anything, and
          will break out-of-tree unsigned modules -- notably the NVIDIA driver.
          Leave null unless you have verified the machine still boots.
        '';
      };

      disableSMT = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Disable hyperthreading to remove cross-thread side channels. Real
          performance cost; only meaningful if you expect to run untrusted code.
        '';
      };
    };

    desktop = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Radios off, aggressive locking, and fewer background services.";
      };

      widget = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install the Plasma 6 "Hardened Mode" applet. Unlike the rest of
          `desktop.*` this applies to both configurations, not just the hardened
          one -- the widget has to survive a switch in either direction to be
          able to report on it. Add it via Add Widgets, or let it appear in the
          system tray, where it stays passive until the machine is hardened.
        '';
      };

      idleLockSeconds = lib.mkOption {
        type = lib.types.int;
        default = 120;
        description = "Idle time before logind locks the session.";
      };

      disableBluetooth = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Turn Bluetooth off entirely and blacklist its modules.";
      };

      disableFingerprint = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Disable fingerprint auth, forcing a password. Biometrics are easier to
          compel and easier to lift off a surface than a passphrase.
        '';
      };

      disableDocker = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Stop the Docker daemon/socket while hardened.";
      };
    };
  };

  config = lib.mkMerge [
    # Tooling has to exist in both configurations. `cfg.enable` is what the
    # specialisation sets, and it force-disables `specialisation.enable` to
    # avoid recursing -- so gating on that alone would leave you inside
    # hardened mode with no `unharden` on PATH.
    (lib.mkIf (cfg.specialisation.enable || cfg.enable) {
      environment.systemPackages = [
        harden
        unharden
        hardenedStatus
        indicatorState
      ]
      ++ lib.optional cfg.desktop.widget plasmoid;

      security.sudo.extraRules = [
        {
          users = [ ];
          groups = [ "wheel" ];
          commands = [
            {
              command = "${hardenedSwitch} switch";
              options = [ "NOPASSWD" ];
            }
            {
              command = "${parentSwitch} switch";
              options = [ "NOPASSWD" ];
            }
            {
              command = "${pkgs.systemd}/bin/systemctl try-restart tailscaled.service";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];

    })

    # Kept separate from the tooling above: this must be keyed on
    # `specialisation.enable` alone, or the specialisation would define a
    # specialisation of itself and recurse forever.
    (lib.mkIf cfg.specialisation.enable {
      specialisation.${cfg.specialisation.name}.configuration = {
        system.nixos.tags = [ cfg.specialisation.name ];
        my.hardened.enable = true;
        my.hardened.specialisation.enable = lib.mkForce false;
      };
    })

    (lib.mkIf cfg.enable {
      environment.etc."hardened-mode".text = ''
        This system is running the "${cfg.specialisation.name}" configuration.
        Run `unharden` to return to the normal one.
      '';
    })

    {
      assertions = [
        {
          # `cfg.enable` exempts the specialisation itself, which force-disables
          # `specialisation.enable` to avoid recursing into itself.
          assertion = cfg.autoArm.enable -> (cfg.specialisation.enable || cfg.enable);
          message = "my.hardened.autoArm requires my.hardened.specialisation.enable (there would be nothing to switch to).";
        }
        {
          assertion = cfg.autoArm.enable -> cfg.trustedNetworks != [ ];
          message = "my.hardened.trustedNetworks is empty -- every network, including home, would arm hardened mode.";
        }
      ];
    }
  ];
}
