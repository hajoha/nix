{
  config,
  pkgs,
  lib,
  ...
}:
let
  signalCli = lib.getExe pkgs.signal-cli;
  configDir = "/var/lib/signal-cli";

  # Minimal stand-in for bbernhard/signal-cli-rest-api: implements the single
  # POST /v2/send route apprise uses, and shells out to signal-cli.
  # Deliberately liberal about field names so an apprise upgrade can't break it.
  signal-webhook = pkgs.writeScriptBin "signal-webhook" ''
    #!${pkgs.python3}/bin/python3
    import base64, json, os, subprocess, sys, tempfile
    from http.server import BaseHTTPRequestHandler, HTTPServer

    SIGNAL_CLI = "${signalCli}"
    CONFIG_DIR = "${configDir}"
    NUMBER = os.environ["SIGNAL_NUMBER"]
    FALLBACK = [r for r in os.environ.get("SIGNAL_RECIPIENTS", NUMBER).split(",") if r]

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):
            sys.stderr.write("signal-webhook: " + fmt % args + "\n")

        def _reply(self, code, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            self._reply(200, {"versions": ["v1", "v2"]})

        def do_POST(self):
            try:
                raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
                payload = json.loads(raw or b"{}")
            except (ValueError, json.JSONDecodeError):
                self._reply(400, {"error": "invalid json"})
                return

            message = payload.get("message") or payload.get("text") or payload.get("body") or ""
            recipients = payload.get("recipients") or FALLBACK
            attachments = payload.get("base64_attachments") or []

            with tempfile.TemporaryDirectory() as tmp:
                cmd = [SIGNAL_CLI, "--config", CONFIG_DIR, "--account", NUMBER,
                       "send", "--message", message]
                for i, blob in enumerate(attachments):
                    if blob.startswith("data:") and "," in blob:
                        blob = blob.split(",", 1)[1]
                    path = os.path.join(tmp, "attachment-%d" % i)
                    try:
                        with open(path, "wb") as fh:
                            fh.write(base64.b64decode(blob))
                    except Exception:
                        continue
                    cmd += ["--attachment", path]
                cmd += recipients
                run = subprocess.run(cmd, capture_output=True, text=True, timeout=120)

            if run.returncode != 0:
                self.log_message("send failed: %s", run.stderr.strip())
                self._reply(500, {"error": run.stderr.strip()})
            else:
                self._reply(201, {"timestamp": run.stdout.strip()})

    HTTPServer(("127.0.0.1", 9922), Handler).serve_forever()
  '';
in
{
  environment.systemPackages = [
    pkgs.signal-cli
    pkgs.qrencode # for the one-time device link below
  ];

  sops.secrets."signal-number" = { };

  sops.templates."signal-webhook.env" = {
    owner = "flathunter";
    content = ''
      SIGNAL_NUMBER=${config.sops.placeholder."signal-number"}
    '';
  };

  systemd.services.signal-webhook = {
    description = "Signal send API for apprise, backed by signal-cli";
    wantedBy = [ "multi-user.target" ];
    before = [ "flathunter.service" ];

    serviceConfig = {
      ExecStart = lib.getExe signal-webhook;
      EnvironmentFile = config.sops.templates."signal-webhook.env".path;
      User = "flathunter";
      Group = "flathunter";
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

  # Signal expects a device to check in. Draining the queue daily keeps the
  # linked device from being treated as stale.
  systemd.services.signal-receive = {
    description = "Drain the Signal receive queue";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${signalCli} --config ${configDir} receive --ignore-attachments";
      User = "flathunter";
      Group = "flathunter";
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
}
