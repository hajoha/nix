{ pkgs, config, ... }:
{
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    pinentry.package = pkgs.pinentry-gnome3;
    # This helps ensure the agent finds the right socket path
    enableExtraSocket = true;
    extraConfig = ''
      disable-ccid
      allow-loopback-pinentry
    '';
  };

  programs.gpg = {
    enable = true;
    settings = {
      # Standard hardening for smartcards
      use-agent = true;
    };
  };
  home.packages = [
    pkgs.opensc
    pkgs.pcsclite
  ];

  home.file.".config/opensc/opensc.conf".text = ''
    app default {
      # Try all drivers that might support an Infineon chip
      card_drivers = starcos, cardos, asepcos;
      # Increase log level so we can see WHY it fails
      debug = 3;
      debug_file = /tmp/opensc.log;
    }
  '';

}
