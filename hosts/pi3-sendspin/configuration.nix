{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  # The nixpkgs package ships both binaries, so don't rely on meta.mainProgram.
  sendspinPlayer = "${pkgs.sendspin-go}/bin/sendspin-player";

  playerYaml = (pkgs.formats.yaml { }).generate "player.yaml" {
    name = "Wohnzimmer";

    # Must be explicit and stable: /etc/sendspin/player.yaml is a read-only
    # store symlink, so the player cannot persist a generated id and would
    # register as a brand new player in Music Assistant after every restart.
    # Use the Pi's eth0 MAC or any fixed string.
    client_id = "b8:27:eb:00:00:00";

    # Empty = auto-discover a Sendspin server (Music Assistant) over mDNS.
    # Pin it if mDNS doesn't cross your VLANs: "ws://192.168.1.50:8927"
    server = "";
    port = 8927;

    # Run `sendspin-player --list-audio-devices` on the Pi once and paste the
    # exact name (case-sensitive, including the "(hw:X,Y)" suffix). Empty =
    # miniaudio's default, which on a Pi is often HDMI rather than your DAC.
    # The player refuses to start on a mismatch instead of failing silently.
    audio_device = "";

    # A Pi 3 on 2.4 GHz wifi wants more headroom than the 150ms default.
    buffer_ms = 250;
    static_delay_ms = 0;

    # opus keeps wire bitrate down; pcm is lighter on the CPU.
    preferred_codec = "opus";

    product_name = "Raspberry Pi 3B";
    manufacturer = "Selfmade";

    # Never start the interactive TUI under systemd; log to the journal.
    daemon = true;
    no_tui = true;
    log_file = "";
  };
in
{
  imports = [
    # Gives us config.system.build.sdImage, u-boot + extlinux and the
    # Raspberry Pi firmware partition. Boots a Pi 3B/3B+ as-is.
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  # miniaudio dlopen()s libasound.so.2 rather than linking it, so if the
  # nixpkgs binary is unwrapped it builds and starts fine but finds no audio
  # backend at all. Check with:
  #   cat $(nix build --print-out-paths nixpkgs#sendspin-go)/bin/sendspin-player | head -5
  # and uncomment this if it's a raw ELF rather than a wrapper script.
  #
  # nixpkgs.overlays = [
  #   (final: prev: {
  #     sendspin-go = prev.sendspin-go.overrideAttrs (old: {
  #       nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.makeWrapper ];
  #       postFixup = (old.postFixup or "") + ''
  #         wrapProgram $out/bin/sendspin-player \
  #           --prefix LD_LIBRARY_PATH : ${final.lib.makeLibraryPath [ final.alsa-lib ]}
  #       '';
  #     });
  #   })
  # ];

  # ── Hardware ──────────────────────────────────────────────────────────────
  hardware.enableRedistributableFirmware = true;

  # The default 16M CMA is not enough on a Pi 3; the console and USB misbehave.
  boot.kernelParams = [
    "cma=64M"
    "console=ttyS1,115200n8"
    "console=tty0"
  ];

  # Onboard analog out. It's genuinely bad — a USB DAC or I2S HAT is worth it
  # for anything you actually listen to.
  boot.kernelModules = [ "snd_bcm2835" ];

  # For a HiFiBerry-style I2S DAC, drop the line above and use instead:
  # hardware.deviceTree.overlays = [{
  #   name = "hifiberry-dac";
  #   dtsFile = "${pkgs.raspberrypifw}/share/raspberrypi/boot/overlays/hifiberry-dac.dtbo";
  # }];

  sdImage.compressImage = false;

  # ── Secrets ───────────────────────────────────────────────────────────────
  # The host key is pre-generated and copied onto the card before first boot,
  # otherwise this is circular: sops needs a key that only exists after boot.
  sops = {
    defaultSopsFile = ./secrets.enc.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets."wifi/home_psk" = { };

    # wpa_supplicant wants a name=value file, so render one from the secret.
    templates."wpa_supplicant.conf".content = ''
      psk_home=${config.sops.placeholder."wifi/home_psk"}
    '';
  };

  # ── Network ───────────────────────────────────────────────────────────────
  networking = {
    hostName = "pi3-sendspin";
    useDHCP = lib.mkDefault true;

    wireless = {
      enable = true;
      secretsFile = config.sops.templates."wpa_supplicant.conf".path;
      networks."mitohnekabel_iot_nomap".pskRaw = "ext:psk_home";
    };

    firewall = {
      enable = true;
      # The server discovers the player over mDNS and then connects *to* it,
      # so both of these are required unless you pin `server` above.
      allowedTCPPorts = [ 8927 ];
      allowedUDPPorts = [ 5353 ];
    };
  };

  # Wi-Fi powersave parks the radio between beacons, which is audible as
  # periodic dropouts in synchronised playback.
  systemd.services.wifi-powersave-off = {
    description = "Disable Wi-Fi power saving";
    wantedBy = [ "multi-user.target" ];
    after = [ "wpa_supplicant.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iw}/bin/iw dev wlan0 set power_save off";
    };
  };

  # ── Sendspin player ───────────────────────────────────────────────────────
  environment.etc."sendspin/player.yaml".source = playerYaml;

  environment.systemPackages = [
    pkgs.sendspin-go
    pkgs.alsa-utils # aplay -l, alsamixer, speaker-test
  ];

  systemd.services.sendspin-player = {
    description = "Sendspin audio player";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "sound.target"
    ];

    serviceConfig = {
      ExecStart = "${sendspinPlayer} --config /etc/sendspin/player.yaml";
      Restart = "always";
      RestartSec = 5;

      DynamicUser = true;
      SupplementaryGroups = [ "audio" ];
      StateDirectory = "sendspin";

      # miniaudio asks for a realtime thread, and a late wakeup is an audible
      # dropout on a 1.2 GHz Pi.
      Nice = -11;
      LimitRTPRIO = 95;
      LimitMEMLOCK = "infinity";
      IOSchedulingClass = "realtime";

      # Needs /dev/snd, so PrivateDevices must stay off.
      PrivateDevices = false;
      DeviceAllow = [ "char-alsa rw" ];

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      RestrictRealtime = false; # we want RT
      SystemCallArchitectures = "native";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
        "AF_NETLINK"
      ];
    };
  };

  # ── System ────────────────────────────────────────────────────────────────
  time.timeZone = "Europe/Berlin";

  # 1 GB of RAM, shared between the audio pipeline and everything else.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # Sync playback depends on a sane clock, and the Pi has no RTC.
  services.chrony.enable = true;
  services.timesyncd.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIocRHpz5SimboTEV6r/YGafvLqNO5qH//VdzcInV/CB johann.hackler@fokus.fraunhofer.de"
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ "root" ];
    auto-optimise-store = true;
    trusted-public-keys = [
      "nix-build:xkoryMgWD1pUN66/xhSmrYNhkyHZtazu4DHGaRySCHM="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
    # The Pi should never build anything itself.
    max-jobs = 0;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Keep the SD card and RAM free.
  documentation.enable = false;
  documentation.nixos.enable = false;
  boot.tmp.useTmpfs = false;

  # ZFS is pulled in by the sd-image base module; the root here is ext4, so
  # the legacy force-import has nothing to do. Opt in to the 26.11 default.
  boot.zfs.forceImportRoot = false;

  system.stateVersion = "25.11";
}
