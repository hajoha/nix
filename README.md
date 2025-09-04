# nix


### update flake
```nix
nix flake update PATH_to_flake.nix`
```


### rebuild nix
```nix
nixos-rebuild switch --flake PATH_TO_FLAKE#HOSTNAME
```

### rebuild remote
```nix
nixos-rebuild \
  --flake .#mySystem \
  --build-host builduser@buildhost \
  --target-host deployuser@deployhost \
  --use-remote-sudo \
  switch
```


### garbage collect old generations
```nix
sudo nix-collect-garbage --delete-older-than 2d
```

### delete unused packages
```nix
nix-store --gc
```