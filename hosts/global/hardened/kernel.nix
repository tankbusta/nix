{ config, lib, pkgs, ... }:

let
  cfg = config.my.hardened;
in
{
  config = lib.mkIf (cfg.enable && cfg.kernel.enable) {
    boot.kernel.sysctl = {
      # Do not hand out kernel addresses or ring-buffer contents to anything
      # unprivileged that manages to run on the box.
      "kernel.kptr_restrict" = 2;
      "kernel.dmesg_restrict" = 1;
      "kernel.perf_event_paranoid" = 3;
      "kernel.sysrq" = 0;

      # 1 = a debugger can still trace processes it started itself, which keeps
      # gdb and friends usable; 2 locks that down too.
      "kernel.yama.ptrace_scope" = cfg.kernel.ptraceScope;

      "kernel.unprivileged_bpf_disabled" = 1;
      "net.core.bpf_jit_harden" = 2;

      "fs.suid_dumpable" = 0;
      # Turning systemd-coredump off is not enough on its own: it leaves
      # core_pattern set to "core", which just writes the dump into the working
      # directory instead. Send it nowhere.
      "kernel.core_pattern" = lib.mkForce "|${pkgs.coreutils}/bin/false";
      "fs.protected_fifos" = 2;
      "fs.protected_regular" = 2;
      "fs.protected_hardlinks" = 1;
      "fs.protected_symlinks" = 1;

      # Ignore anything the local network tries to tell us about routing.
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.secure_redirects" = 0;
      "net.ipv4.conf.default.secure_redirects" = 0;
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;
      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv4.conf.default.accept_source_route" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;
      "net.ipv6.conf.all.accept_source_route" = 0;
      "net.ipv6.conf.default.accept_source_route" = 0;

      "net.ipv4.tcp_syncookies" = 1;
      "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
      "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

      # Deliberately NOT setting net.ipv4.conf.*.rp_filter: Tailscale relaxes
      # reverse-path filtering for client routing, and forcing it strict here
      # breaks exit nodes and subnet routes.
    };

    # Rotating IPv6 privacy addresses, so the venue cannot follow one stable v6
    # address around the building. Goes through the NixOS option rather than a
    # raw sysctl, which network-interfaces.nix already owns.
    #
    # The value names are a trap: "default" (use_tempaddr=2) is the strong one
    # that actually *sources* traffic from the temporary address, while
    # "enabled" (=1) merely generates one and keeps using EUI-64.
    networking.tempAddresses = "default";

    security.protectKernelImage = true;
    security.allowSimultaneousMultithreading = !cfg.kernel.disableSMT;

    security.lockKernelModules = cfg.kernel.lockModules;

    systemd.coredump.enable = false;

    boot.kernelParams = [
      "slab_nomerge"
      "init_on_alloc=1"
      "init_on_free=1"
      "page_alloc.shuffle=1"
      "randomize_kstack_offset=on"
      "vsyscall=none"
    ]
    ++ lib.optional (cfg.kernel.lockdown != null) "lockdown=${cfg.kernel.lockdown}";

    boot.blacklistedKernelModules = [
      "dccp"
      "sctp"
      "rds"
      "tipc"
      "n-hdlc"
      "ax25"
      "netrom"
      "x25"
      "rose"
      "decnet"
      "econet"
      "af_802154"
      "ipx"
      "appletalk"
      "psnap"
      "p8023"
      "p8022"
      "can"
      "atm"
      "cramfs"
      "freevxfs"
      "jffs2"
      "hfs"
      "hfsplus"
      "udf"
    ];

    # No editing the kernel command line from the boot menu
    boot.loader.systemd-boot.editor = lib.mkForce false;

    assertions = [
      {
        assertion = cfg.kernel.lockdown != null -> config.boot.secureboot.enable;
        message = ''
          my.hardened.kernel.lockdown is set but boot.secureboot.enable is not.
          Lockdown without verified boot is theatre -- and it will refuse to load
          unsigned out-of-tree modules such as the NVIDIA driver.
        '';
      }
    ];
  };
}
