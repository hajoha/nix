# vars.nix
{
  hosts = {
    nixinflux = {
      networking = {
        hostName = "nixinflux";
        # Define the VLAN
        vlans.vlan3001 = {
          id = 3001;
          interface = "eth0"; # The physical interface inside the LXC
        };
        # Assign the IP to the VLAN interface specifically
        interfaces.vlan3001.ipv4.addresses = [{
          address = "10.60.1.26";
          prefixLength = 24;
        }];
        # Specific firewall for this service
        firewall.interfaces.vlan3001.allowedTCPPorts = [ 8086 ];
      };
      services = [ "influxv2" ];
    };
  };
}