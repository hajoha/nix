# (Re)installing the homelab host

Boot a NixOS installer from USB **in UEFI mode** on the box, ssh into it and
copy the repo over (`rsync … ./ root@<live-ip>:/root/home-nix/`, without
`.git`). Then:

```bash
export NIX_CONFIG="experimental-features = nix-command flakes"
F=path:/root/home-nix#homelab
nix run github:nix-community/disko/latest -- --mode destroy,format,mount --flake $F
nixos-install --flake $F --no-root-passwd --no-channel-copy --option accept-flake-config true
efibootmgr        # "Linux Boot Manager" must be there and first
```

- disko only touches `params.rootDisk`; the HDD pool is not part of it.
- The board (Fujitsu D3417-A) only boots the NVMe through a firmware boot
  entry. `nixos-install` writes it, but only from an installer booted in
  UEFI mode. CSM off, Secure Boot off.
- The host gets a fresh ssh key, and so does every container whose key is
  not in `container-keys.enc.json`; their secrets have to be re-encrypted:
  set `startContainers = false` before installing, then on the host
  `systemctl start homelab-container-prepare; homelab-age-keys`, put the keys
  into `inventory/keys.nix` (`hosts.homelab`) and `inventory/nodes.nix`
  (`age`, only the host-generated ones), `nix run .#sops-config`,
  `for f in $(git ls-files '*.enc.*'); do sops updatekeys -y "$f"; done`,
  set `startContainers = true` and deploy.
- Storage box: add `/etc/ssh/ssh_host_ed25519_key.pub` of the new host with
  `… | ssh -p23 u557074@u557074.your-storagebox.de install-ssh-key` from a
  machine that already has access.

## After every reboot

The HDD pool is encrypted and not unlocked automatically; containers with
data volumes (postgres, immich, arr, opencloud) and everything that needs
them wait for it and start by themselves afterwards:

```bash
zfs load-key threetbpool && zfs mount -a
journalctl -u 'homelab-data-*' -u 'container@*' -f     # watch them come up
```

