{ config, lib, pkgs, ... }:

let
  cfg = config.my.hardened;

  # Temporarily point the active link at the network's own resolver so a
  # captive portal can be worked through, then hand DNS back. Uses resolvectl
  # rather than editing NetworkManager profiles, so nothing persists -- a
  # reconnect or `hardened-dns secure` reverts it.
  hardenedDns = pkgs.writeShellScriptBin "hardened-dns" ''
    set -eu
    iface=$(${pkgs.iproute2}/bin/ip route show default | ${pkgs.gawk}/bin/awk '{print $5; exit}')
    gw=$(${pkgs.iproute2}/bin/ip route show default | ${pkgs.gawk}/bin/awk '{print $3; exit}')

    if [ -z "''${iface:-}" ]; then
      echo "no default route." >&2
      exit 1
    fi

    case "''${1:-}" in
      portal)
        echo "pointing $iface DNS at $gw in the clear (captive portal mode)."
        ${pkgs.systemd}/bin/resolvectl dns "$iface" "$gw"
        ${pkgs.systemd}/bin/resolvectl domain "$iface" '~.'
        ${pkgs.systemd}/bin/resolvectl dnsovertls "$iface" no
        echo "run 'hardened-dns secure' as soon as you are through."
        ;;
      secure)
        ${pkgs.systemd}/bin/resolvectl revert "$iface"
        echo "$iface reverted to the configured resolvers."
        ;;
      *)
        echo "usage: hardened-dns portal|secure" >&2
        exit 1
        ;;
    esac
  '';
in
{
  config = lib.mkMerge [
    # Deliberately present in BOTH configurations, not just the hardened one.
    #
    # Adding or removing the resolver across a switch is what broke DNS the
    # first time this ran: the hardened config pulled systemd-resolved in, and
    # switching back deleted the unit out from under the still-running process,
    # which then died on its watchdog. Meanwhile Tailscale -- which had already
    # taken over /etc/resolv.conf and points it at MagicDNS -- was left
    # forwarding to an upstream that no longer existed, so nothing resolved at
    # all, in the *normal* configuration.
    #
    # With resolved present on both sides, a switch only ever reconfigures it,
    # and Tailscale keeps talking to it over D-Bus instead of seizing
    # resolv.conf. That also keeps DNS-over-TLS intact, which the resolv.conf
    # takeover would otherwise bypass in plaintext.
    (lib.mkIf ((cfg.specialisation.enable || cfg.enable) && cfg.network.enable) {
      services.resolved.enable = true;
      networking.networkmanager.dns = "systemd-resolved";
    })

    (lib.mkIf (cfg.enable && cfg.network.enable) {
    networking.firewall = {
      enable = lib.mkForce true;
      rejectPackets = false;
      allowPing = false;
      logRefusedConnections = true;
    };

    # Stop announcing ourselves on the local segment. On a con network the
    # hostname, service list and OS fingerprint are free intel for everyone
    # else on the same SSID.
    services.avahi.enable = lib.mkForce false;
    services.samba.enable = lib.mkForce false;
    services.printing.enable = lib.mkForce false;

    networking.networkmanager = {
      # A fresh MAC per connection, and per scan, so the venue cannot trivially
      # correlate you across APs or across days.
      wifi.macAddress = "random";
      wifi.scanRandMacAddress = true;
      ethernet.macAddress = "random";

      dns = "systemd-resolved";

      connectionConfig = {
        # 0 = no mDNS / LLMNR responder or resolver on any connection.
        "connection.mdns" = 0;
        "connection.llmnr" = 0;
      }
      // lib.optionalAttrs cfg.network.disableWifiAutoconnect {
        # Anti-KARMA. Without this, anything broadcasting the name of a saved
        # network gets a free association attempt from you the moment you walk
        # into range.
        "connection.autoconnect" = false;
      }
      // lib.optionalAttrs cfg.network.ignoreDhcpDns {
        "ipv4.ignore-auto-dns" = true;
        "ipv6.ignore-auto-dns" = true;
      };
    };

    # Only the *settings* change here -- `enable` is set unconditionally above
    # so the unit never appears or disappears across a switch.
    services.resolved = {
      settings.Resolve = {
        DNS = cfg.network.dns;
        FallbackDNS = [ ];
        DNSOverTLS = cfg.network.dnsOverTls;
        DNSSEC = "allow-downgrade";
        LLMNR = "false";
        MulticastDNS = "false";
      };
    };

    environment.systemPackages = [ hardenedDns ];

    # Force every packet out through a Tailscale exit node. Everything the
    # venue sees is then a single WireGuard flow.
    systemd.services.hardened-exit-node = lib.mkIf (cfg.network.exitNode != null) {
      description = "Pin traffic to Tailscale exit node ${cfg.network.exitNode}";
      after = [ "tailscaled.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      requires = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 10;
      };
      script = ''
        ${config.services.tailscale.package}/bin/tailscale set \
          --exit-node=${cfg.network.exitNode} \
          --exit-node-allow-lan-access=false
      '';
    };
    })
  ];
}
