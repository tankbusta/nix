{ config, lib, pkgs, ... }:

let
  cfg = config.my.hardened;

  hardenedSwitch = "/run/current-system/specialisation/${cfg.specialisation.name}/bin/switch-to-configuration";

  trusted = lib.concatMapStringsSep " " lib.escapeShellArg cfg.trustedNetworks;

  autoArmScript = pkgs.writeShellScript "hardened-autoarm" ''
    iface="$1"
    action="$2"

    log() { ${pkgs.util-linux}/bin/logger -t hardened-autoarm "$@"; }

    # Only "up" carries connection identity. "connectivity-change" fires often
    # and sets no CONNECTION_ID, so acting on it meant comparing an empty name
    # against the trusted list, never matching, and arming on every network --
    # including the trusted one.
    if [ "$action" != "up" ]; then
      exit 0
    fi

    # Only physical links describe "what network am I on". The dispatcher also
    # fires for tailscale0, docker0 and friends, and those names never match
    # the trusted list -- which is how a VPN interface coming up was arming the
    # machine while it sat on the trusted home wifi. Virtual interfaces have no
    # `device` symlink in sysfs; physical ones do.
    if [ -z "$iface" ] || [ ! -e "/sys/class/net/$iface/device" ]; then
      exit 0
    fi

    if [ -e /etc/hardened-mode ]; then
      exit 0
    fi

    if [ ! -x ${hardenedSwitch} ]; then
      log "no hardened specialisation in this generation"
      exit 0
    fi

    # Switching configurations restarts NetworkManager, which emits a fresh
    # "up" within seconds. Without this cooldown, `unharden` is immediately
    # undone by the dispatcher it just triggered -- an arm/disarm loop, each
    # iteration firing another notification.
    now=$(${pkgs.coreutils}/bin/date +%s)
    activated=$(${pkgs.coreutils}/bin/stat -c %Y /run/current-system 2>/dev/null || echo 0)
    age=$((now - activated))
    if [ "$age" -lt ${toString cfg.autoArm.cooldownSeconds} ]; then
      log "system reconfigured ''${age}s ago, not re-arming yet"
      exit 0
    fi

    # NetworkManager is synchronously waiting for this script, so asking it
    # anything (nmcli) can block until the dispatcher times out. `iw` reads the
    # interface directly and cannot deadlock against NM.
    name="''${CONNECTION_ID:-}"
    ssid=$(${pkgs.iw}/bin/iw dev "$iface" link 2>/dev/null \
      | ${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*SSID: //p')

    for t in ${trusted}; do
      if [ "$name" = "$t" ] || [ "$ssid" = "$t" ]; then
        log "trusted network '$t', staying in normal mode"
        exit 0
      fi
    done

    # Unknown networks arm too -- failing safe is the whole point. But say so,
    # because "could not identify the network" and "identified a hostile one"
    # deserve different levels of trust in the log.
    if [ -z "$name" ] && [ -z "$ssid" ]; then
      log "could not identify network on $iface -- arming anyway"
      label="an unidentified network"
    else
      label="''${ssid:-$name}"
    fi

    if ${pkgs.systemd}/bin/systemctl is-active --quiet hardened-autoarm-switch.service; then
      log "a switch is already in flight"
      exit 0
    fi

    log "untrusted network (name='$name' ssid='$ssid') -- arming hardened mode"

    ${lib.optionalString cfg.autoArm.notify ''
      for d in /run/user/*; do
        [ -S "$d/bus" ] || continue
        uid="$(${pkgs.coreutils}/bin/basename "$d")"
        ${pkgs.systemd}/bin/systemd-run --collect --uid="$uid" \
          --setenv=DBUS_SESSION_BUS_ADDRESS="unix:path=$d/bus" \
          ${pkgs.libnotify}/bin/notify-send -u critical \
          -a "Hardened Mode" \
          -h string:x-canonical-private-synchronous:hardened-mode \
          "Hardened mode armed" \
          "Joined $label, which is not a trusted network. Run 'unharden' to undo." \
          >/dev/null 2>&1 || true
      done
    ''}

    # Detached: NetworkManager kills dispatcher scripts that take too long, and
    # a full switch-to-configuration takes longer than that.
    ${pkgs.systemd}/bin/systemd-run --no-block --collect \
      --unit=hardened-autoarm-switch \
      ${hardenedSwitch} switch
  '';
in
{
  config = lib.mkIf cfg.autoArm.enable {
    networking.networkmanager.dispatcherScripts = [
      {
        type = "basic";
        source = autoArmScript;
      }
    ];
  };
}
