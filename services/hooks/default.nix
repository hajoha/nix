# GitHub webhooks for the homelab host (hosts/homelab/ci.nix).
#
# nix-nginx forwards https://hooks.<domain>/hooks/{deploy,preview} here. The
# webhook server checks GitHub's signature (webhook-secret) and the event,
# then only drops an empty file into /run/homelab-hooks/queue, a directory
# shared with the host:
#
#   deploy          push to main
#   preview-<pr>    PR from a branch of this repo into main opened / pushed to
#
# The host watches the directory, starts the matching unit and deletes the
# file. Nothing else crosses: no network path to the host, the host fetches
# the repo and asks the GitHub API itself.
#
# Inactive until ./secrets.enc.yaml exists (key `webhook-secret`).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.homelab) nodes;
  repo = "hajoha/nix";
  queue = "/run/homelab-hooks/queue";
  secretsFile = ./secrets.enc.yaml;

  hook = pkgs.writeShellApplication {
    name = "homelab-hook";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      case ''${1:-} in
        deploy) touch ${queue}/deploy ;;
        preview)
          [[ ''${2:-} =~ ^[0-9]+$ ]] || { echo "bad PR number" >&2; exit 2; }
          touch "${queue}/preview-$2"
          ;;
        *) echo "usage: homelab-hook deploy | preview <pr>" >&2; exit 2 ;;
      esac
    '';
  };

  # trigger rule: signed with our secret, plus `rules`
  signed = rules: ''
    {"and": [
      {"match": {"type": "payload-hmac-sha256",
                 "secret": "{{ getenv "WEBHOOK_SECRET" | js }}",
                 "parameter": {"source": "header", "name": "X-Hub-Signature-256"}}},
      ${lib.concatStringsSep ",\n" rules}
    ]}
  '';
  match = type: source: name: value: ''
    {"match": {"type": "${type}", "${if type == "regex" then "regex" else "value"}": "${value}",
               "parameter": {"source": "${source}", "name": "${name}"}}}
  '';
in
lib.mkIf (builtins.pathExists secretsFile) {
  sops.secrets.webhook-secret.sopsFile = secretsFile;
  sops.templates."webhook.env".content = ''
    WEBHOOK_SECRET=${config.sops.placeholder.webhook-secret}
  '';

  services.webhook = {
    enable = true;
    port = nodes.nix-hooks.port;
    hooksTemplated = {
      deploy = ''
        {
          "id": "deploy",
          "http-methods": ["POST"],
          "execute-command": "${lib.getExe hook}",
          "pass-arguments-to-command": [{"source": "string", "name": "deploy"}],
          "response-message": "deploy queued",
          "trigger-rule": ${
            signed [
              (match "value" "header" "X-GitHub-Event" "push")
              (match "value" "payload" "ref" "refs/heads/main")
            ]
          }
        }
      '';
      preview = ''
        {
          "id": "preview",
          "http-methods": ["POST"],
          "execute-command": "${lib.getExe hook}",
          "pass-arguments-to-command": [
            {"source": "string", "name": "preview"},
            {"source": "payload", "name": "pull_request.number"}
          ],
          "response-message": "preview queued",
          "trigger-rule": ${
            signed [
              (match "value" "header" "X-GitHub-Event" "pull_request")
              (match "regex" "payload" "action" "^(opened|reopened|synchronize)$")
              (match "value" "payload" "pull_request.base.ref" "main")
              (match "value" "payload" "pull_request.head.repo.full_name" repo)
            ]
          }
        }
      '';
    };
  };

  systemd.services.webhook.serviceConfig = {
    EnvironmentFile = config.sops.templates."webhook.env".path;
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ReadWritePaths = [ queue ];
    ProtectHome = true;
    PrivateTmp = true;
  };

  # the shared directory is bind-mounted from the host (hosts/homelab/ci.nix)
  systemd.tmpfiles.rules = [ "d ${queue} 0700 webhook webhook -" ];

  # only nix-nginx may talk to the webhook server
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p tcp -s ${nodes.nix-nginx.ip} --dport ${toString nodes.nix-hooks.port} -j nixos-fw-accept
  '';
}
