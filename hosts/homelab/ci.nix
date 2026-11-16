# GitHub → homelab via webhooks (no timer, no GitHub runner on the host):
#
#   https://hooks.<domain>/hooks/preview   PR opened / pushed to
#       → homelab-preview@<pr>: builds the PR's system, comments version /
#         CVE diffs (homelab-preview), sets the status "homelab/preview"
#   https://hooks.<domain>/hooks/deploy    push to main
#       → homelab-deploy: builds main, switches, health-checks, rolls back
#         if something broke; status "homelab/deploy" + comment on the PR
#
# The webhooks end in the nix-hooks container (services/hooks, service
# VLAN, behind nix-nginx), which checks GitHub's signature and drops a file
# into a directory shared with the host. homelab-hooks.path notices it and
# starts the unit. The units fetch the repo (public, https) and ask the
# GitHub API themselves, and only build PRs from branches of this repo,
# never forks.
#
# GitHub reporting needs ./github.enc.yaml (key `token`: fine-grained PAT,
# see README). homelab-deploy.service exists either way
# (systemctl start homelab-deploy).
{
  config,
  lib,
  pkgs,
  inventory,
  params,
  ...
}:
let
  secretsFile = ./github.enc.yaml;
  enable = builtins.pathExists secretsFile;

  # shared with nix-hooks; it may only create files here
  hooksDir = "/var/lib/homelab/hooks";

  repo = "hajoha/nix";
  gitUrl = "https://github.com/${repo}.git"; # for git
  repoUrl = "git+${gitUrl}"; # for nix

  # "<node> <port>" for every container that is started automatically
  nodesFile = pkgs.writeText "homelab-health-nodes" (
    lib.concatStrings (
      lib.mapAttrsToList (name: n: "${name} ${toString (n.port or 0)}\n") (
        lib.filterAttrs (_: n: n.service != null && n.autoStart) inventory.nodes
      )
    )
  );

  env = {
    REPO = repo;
    REPO_URL = repoUrl;
    GIT_URL = gitUrl;
  };
  githubLib = builtins.readFile ./ci/github.sh;

  deployRev = pkgs.writeShellApplication {
    name = "homelab-deploy-rev";
    runtimeInputs = [
      config.nix.package
      config.systemd.package
      config.boot.zfs.package
      pkgs.git
      pkgs.util-linux
      pkgs.iproute2
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
    ];
    runtimeEnv = env // {
      NODES = "${nodesFile}";
      POOL = params.pool;
      GRACE = "90";
    };
    text = builtins.readFile ./ci/deploy-rev.sh;
  };

  deploy = pkgs.writeShellApplication {
    name = "homelab-deploy";
    runtimeInputs = [
      deployRev
      pkgs.git
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    runtimeEnv = env;
    text = githubLib + builtins.readFile ./ci/deploy.sh;
  };

  preview = pkgs.writeShellApplication {
    name = "homelab-preview";
    runtimeInputs = [
      pkgs.nvd
      pkgs.vulnix
      pkgs.jq
      pkgs.coreutils
      pkgs.gnused
      pkgs.gawk
      pkgs.gnugrep
    ];
    # CVEs checked by hand, see the file
    runtimeEnv.VULNIX_WHITELIST = "${./ci/vulnix-whitelist.toml}";
    text = builtins.readFile ./ci/preview.sh;
  };

  previewPr = pkgs.writeShellApplication {
    name = "homelab-preview-pr";
    runtimeInputs = [
      preview
      config.nix.package
      pkgs.git
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
    ];
    runtimeEnv = env;
    text = githubLib + builtins.readFile ./ci/preview-pr.sh;
  };

in
lib.mkMerge [
  {
    environment.systemPackages = [
      preview
      deploy
    ];

    # the flake's binary caches, also for builds by non-root users (preview)
    nix.settings = {
      extra-substituters = [
        "https://noctalia.cachix.org"
        "https://tranquil.cachix.org"
      ];
      extra-trusted-public-keys = [
        "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
        "tranquil.cachix.org-1:PoO+mGL6a6LcJiPakMDHN4E218/ei/7v2sxeDtNkSRg="
      ];
    };

    # homelab-deploy.service: deploy main, check, roll back
    systemd.services.homelab-deploy = {
      description = "Deploy main of ${repo}";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # it is running while the switch happens
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe deploy;
        LoadCredential = lib.mkIf enable [ "token:${config.sops.secrets.github-token.path}" ];
      };
    };

    # nix-hooks → host: one empty file per event in ${hooksDir}/queue
    systemd.tmpfiles.rules = [ "d ${hooksDir} 0755 root root -" ];
    containers.nix-hooks.bindMounts."/run/homelab-hooks" = {
      hostPath = hooksDir;
      isReadOnly = false;
    };
    systemd.paths.homelab-hooks = {
      wantedBy = [ "paths.target" ];
      pathConfig.DirectoryNotEmpty = "${hooksDir}/queue";
    };
    systemd.services.homelab-hooks = {
      description = "Start units for queued GitHub webhooks";
      path = [ config.systemd.package ];
      serviceConfig.Type = "oneshot";
      # file names come from the container: only these exact forms count
      script = ''
        for f in ${hooksDir}/queue/*; do
          [ -e "$f" ] || [ -L "$f" ] || continue
          name=$(basename "$f")
          rm -rf -- "$f"
          case $name in
            deploy)
              # a running deploy picks up newer commits itself
              systemctl start --no-block homelab-deploy.service || true
              ;;
            preview-*)
              pr=''${name#preview-}
              if [[ $pr =~ ^[0-9]{1,7}$ ]]; then
                # a new push to the PR restarts its preview
                systemctl restart --no-block "homelab-preview@$pr.service" || true
              fi
              ;;
            *) echo "ignoring $name" ;;
          esac
        done
      '';
    };
  }

  (lib.mkIf enable {
    sops.secrets.github-token = {
      sopsFile = secretsFile;
      key = "token";
    };
    # homelab-preview@<pr>.service: build a PR, comment the preview.
    # Unprivileged (nix builds through the daemon).
    systemd.services."homelab-preview@" = {
      description = "Deploy preview of PR #%i";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      restartIfChanged = false;
      environment = {
        HOME = "/var/cache/homelab-preview";
        VULNIX_CACHE = "/var/cache/homelab-preview/vulnix";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe previewPr} %i";
        DynamicUser = true;
        CacheDirectory = "homelab-preview";
        LoadCredential = [ "token:${config.sops.secrets.github-token.path}" ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  })
]
