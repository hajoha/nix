# Typed view of the inventory for every LXC, set by flake/lxc.nix.
#
#   config.homelab.domain                 "hackler.io"
#   config.homelab.nodes.<n>.ip / .port   raw address
#   config.homelab.nodes.<n>.addr         "http://<ip>:<port>"
#   config.homelab.nodes.<n>.fqdn         "<sub or hostname>.<domain>"
#   config.homelab.nodes.<n>.url          "https://<fqdn>"
#   config.homelab.sso.issuer             Keycloak realm issuer URL
#   config.homelab.databases              services with a DB on nix-postgres
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.homelab;

  nodeType = types.submodule (
    { config, ... }:
    {
      options = {
        ip = mkOption { type = types.str; };
        port = mkOption {
          type = types.port;
          description = "Primary service port.";
        };
        hostname = mkOption { type = types.str; };
        sub = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Public subdomain, if it differs from `hostname`.";
        };

        fqdn = mkOption {
          type = types.str;
          readOnly = true;
          default = "${if config.sub != null then config.sub else config.hostname}.${cfg.domain}";
        };
        url = mkOption {
          type = types.str;
          readOnly = true;
          default = "https://${config.fqdn}";
        };
        addr = mkOption {
          type = types.str;
          readOnly = true;
          default = "http://${config.ip}:${toString config.port}";
        };
      };
    }
  );
in
{
  options.homelab = {
    domain = mkOption { type = types.str; };

    nodes = mkOption {
      type = types.attrsOf nodeType;
      default = { };
    };

    databases = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Services with a database + user on nix-postgres; each one's password
        comes from services/<name>/postgres.enc.yaml.
      '';
    };

    sso = {
      realm = mkOption { type = types.str; };
      node = mkOption {
        type = types.str;
        default = "nix-keycloak";
      };
      issuer = mkOption {
        type = types.str;
        readOnly = true;
        default = "${cfg.nodes.${cfg.sso.node}.url}/realms/${cfg.sso.realm}";
      };
    };
  };
}
