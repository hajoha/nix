# Signal alerts from the VPS: signal-cli with its own number, behind a tiny
# HTTP bridge that Grafana (homelab, via Traefik) and Gatus (local) post to.
# Only with `signalAlerts = true` in inventory/default.nix.
#
#   Grafana ──https──▶ Traefik signal.monitor.<domain> ──┐
#   Gatus   ──────────────────────────────────────────────┴▶ bridge 127.0.0.1:9922
#                                                            └▶ signal-cli send
#
# POST /v2/send with "Authorization: Bearer <token>" and a JSON body; the
# text comes from "title" + "message" (Grafana's webhook payload) or
# "message" alone (Gatus). Recipients: from the body ("recipients") or the
# default list from sops.
#
# sops (hosts/hetzner-vps-01/secrets.enc.yaml):
#   signal:
#     number:     "+49…"            the sender, its own Signal account
#     recipients: "+49…,+49…"       who gets the alerts
#     token:      random string     bearer token for the bridge
#
# The sender needs its OWN number: messages from a device linked to your
# account show up as sent by you and do not notify. signal-cli's key store
# changes with every message, so it lives in /var/lib/signal-cli, not in
# sops. Register once (docs/monitoring.md, "Signal"):
#
#   sudo -u signal signal-cli --config /var/lib/signal-cli -a +49… register --captcha 'signalcaptcha://…'
#   sudo -u signal signal-cli --config /var/lib/signal-cli -a +49… verify 123-456
{
  config,
  lib,
  pkgs,
  inventory,
  ...
}:
let
  signalCli = lib.getExe pkgs.signal-cli;
  configDir = "/var/lib/signal-cli";
  listen = 9922;

  bridge = pkgs.writeScriptBin "signal-alert-bridge" ''
    #!${pkgs.python3}/bin/python3
    import hmac, json, os, subprocess, sys
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    SIGNAL_CLI = "${signalCli}"
    CONFIG_DIR = "${configDir}"
    NUMBER = os.environ["SIGNAL_NUMBER"]
    TOKEN = os.environ["SIGNAL_TOKEN"].encode()
    DEFAULT = [r.strip() for r in os.environ.get("SIGNAL_RECIPIENTS", "").split(",") if r.strip()]
    MAX = 4000  # keep messages readable; Grafana's default text can be long

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):
            sys.stderr.write("signal-alert-bridge: " + fmt % args + "\n")

        def reply(self, code, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def authorized(self):
            got = self.headers.get("Authorization", "").removeprefix("Bearer ").encode()
            return hmac.compare_digest(got, TOKEN)

        def do_GET(self):
            self.reply(200, {"ok": True})  # health check, no secrets

        def do_POST(self):
            if not self.authorized():
                self.reply(401, {"error": "unauthorized"})
                return
            try:
                raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
                p = json.loads(raw or b"{}")
            except ValueError:
                self.reply(400, {"error": "invalid json"})
                return

            title = (p.get("title") or "").strip()
            text = (p.get("message") or p.get("text") or p.get("body") or "").strip()
            message = (title + "\n\n" + text).strip() if title and not text.startswith(title) else text or title
            if len(message) > MAX:
                message = message[:MAX] + "\n…"
            recipients = p.get("recipients") or DEFAULT
            if not message or not recipients:
                self.reply(400, {"error": "no message or no recipients"})
                return

            cmd = [SIGNAL_CLI, "--config", CONFIG_DIR, "--account", NUMBER,
                   "send", "--message", message, *recipients]
            run = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            if run.returncode != 0:
                self.log_message("send failed: %s", run.stderr.strip())
                self.reply(502, {"error": "signal-cli failed"})
            else:
                self.reply(201, {"sent": len(recipients)})

    ThreadingHTTPServer(("127.0.0.1", ${toString listen}), Handler).serve_forever()
  '';
in
{
  options.homelab.signalBridge = lib.mkOption {
    type = lib.types.str;
    default = "http://127.0.0.1:${toString listen}";
    readOnly = true;
    description = "Address of the Signal bridge on this machine.";
  };

  config = lib.mkIf inventory.signalAlerts {
    users.users.signal = {
      isSystemUser = true;
      group = "signal";
      home = configDir;
    };
    users.groups.signal = { };

    # for registering / debugging by hand (sudo -u signal signal-cli …)
    environment.systemPackages = [ pkgs.signal-cli ];

    sops.secrets = {
      "signal/number" = { };
      "signal/recipients" = { };
      "signal/token" = { };
    };
    sops.templates."signal-bridge.env" = {
      owner = "signal";
      content = ''
        SIGNAL_NUMBER=${config.sops.placeholder."signal/number"}
        SIGNAL_RECIPIENTS=${config.sops.placeholder."signal/recipients"}
        SIGNAL_TOKEN=${config.sops.placeholder."signal/token"}
      '';
    };

    systemd.services.signal-alert-bridge = {
      description = "HTTP bridge for alerts to Signal (signal-cli)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = lib.getExe bridge;
        EnvironmentFile = config.sops.templates."signal-bridge.env".path;
        User = "signal";
        Group = "signal";
        StateDirectory = "signal-cli";
        StateDirectoryMode = "0700";
        Restart = "on-failure";
        RestartSec = 10;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    # Signal drops accounts that never fetch their messages; receive daily.
    systemd.services.signal-receive = {
      description = "Fetch pending Signal messages (keeps the account alive)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeShellScript "signal-receive" ''
          set -a; . ${config.sops.templates."signal-bridge.env".path}; set +a
          exec ${signalCli} --config ${configDir} --account "$SIGNAL_NUMBER" receive --ignore-attachments
        ''}";
        User = "signal";
        Group = "signal";
        StateDirectory = "signal-cli";
      };
    };
    systemd.timers.signal-receive = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };
  };
}
