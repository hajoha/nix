{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nmap
    ipcalc
    mtr
    iperf3
    dnsutils
    ldns
    aria2
    socat
    mtr
    libqmi
    tie
  ];
}
