#!/usr/bin/env bash
# WireGuard peers of hetzner-vps-01 (wg0, 10.60.71.0/24), see usage below.
# In `nix develop` this is `wg-peer`; run it anywhere inside the repo.
set -euo pipefail

for t in sops wg jq qrencode; do
  if ! command -v "$t" >/dev/null && [ -z "${WG_PEER_IN_NIX_SHELL:-}" ]; then
    export WG_PEER_IN_NIX_SHELL=1
    exec nix --extra-experimental-features 'nix-command flakes' shell \
      nixpkgs#sops nixpkgs#wireguard-tools nixpkgs#jq nixpkgs#qrencode -c bash "$0" "$@"
  fi
done

me=$(basename "$0")
here=$PWD
root=$(git rev-parse --show-toplevel 2>/dev/null) ||
  root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null) ||
  { echo "error: run $me inside the home-nix repo" >&2; exit 1; }
[ -f "$root/hosts/hetzner-vps-01/wireguard-peers.json" ] ||
  { echo "error: $root is not the home-nix repo" >&2; exit 1; }
cd "$root" # sops reads .sops.yaml here
host=hosts/hetzner-vps-01
peers=$host/wireguard-peers.json
keys=wireguard.enc.yaml
endpoint=89.167.0.183:51820
net=10.60.71
serverIp=$net.1

die() {
  echo "error: $*" >&2
  exit 1
}
usage() {
  cat >&2 <<EOF
WireGuard peers of hetzner-vps-01. Peers reach only the VPS ($serverIp).
Needs your age key for sops.

  $me list
  $me add <name> [ip]      new keys into sops, entry in wireguard-peers.json
  $me conf <name> [file]   client config to stdout, or to a file (mode 600)
  $me qr <name>            the same config as a QR code

After add: commit and deploy hetzner-vps-01.
EOF
  exit 1
}
has() { jq -e --arg k "$1" --arg v "$2" 'any(.[]; .[$k] == $v)' "$peers" >/dev/null; }
secret() { sops decrypt --extract "$2" "$host/$1"; }

# Each step checked by hand: `set -e` does not catch failures inside $(...).
conf() {
  local p file ip priv psk vps
  p=$(jq -e --arg n "$1" '.[] | select(.name == $n)' "$peers") || die "no peer '$1', see: $me list"
  file=$(jq -r --arg d "$keys" '.sopsFile // $d' <<<"$p")
  ip=$(jq -r .ip <<<"$p")
  priv=$(secret "$file" "[\"$1\"][\"private\"]") || die "cannot decrypt $1's private key"
  psk=$(secret "$file" "[\"$1\"][\"psk\"]") || die "cannot decrypt $1's preshared key"
  vps=$(secret secrets.enc.yaml '["wg.privat"]' | wg pubkey) || die "cannot get the vps public key"
  [ -n "$priv" ] && [ -n "$psk" ] && [ -n "$vps" ] || die "empty key for $1"
  printf '[Interface]\nPrivateKey = %s\nAddress = %s/32\n\n[Peer]\nPublicKey = %s\nPresharedKey = %s\nEndpoint = %s\nAllowedIPs = %s/32\nPersistentKeepalive = 25\n' \
    "$priv" "$ip" "$vps" "$psk" "$endpoint" "$serverIp"
}

add() {
  local name=$1 ip=${2:-} i priv pub psk
  [[ $name =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "name: lowercase letters, digits and -"
  ! has name "$name" || die "'$name' exists"
  if [ -z "$ip" ]; then
    for i in $(seq 2 254); do
      has ip "$net.$i" || {
        ip=$net.$i
        break
      }
    done
  fi
  if ! [[ $ip =~ ^10\.60\.71\.([0-9]+)$ ]] || ((BASH_REMATCH[1] < 2 || BASH_REMATCH[1] > 254)); then
    die "ip must be $net.2 to $net.254"
  fi
  ! has ip "$ip" || die "$ip is taken"

  priv=$(wg genkey)
  pub=$(wg pubkey <<<"$priv")
  psk=$(wg genpsk)
  # via stdin so the keys never show up in `ps`
  printf '{"public":"%s","private":"%s","psk":"%s"}' "$pub" "$priv" "$psk" |
    sops set --value-stdin "$host/$keys" "[\"$name\"]"
  jq --arg n "$name" --arg ip "$ip" --arg k "$pub" '. + [{name: $n, ip: $ip, publicKey: $k}]' \
    "$peers" >"$peers.tmp"
  mv "$peers.tmp" "$peers"
  echo "added $name ($ip). Commit and deploy hetzner-vps-01, then: $me conf $name   or   $me qr $name"
}

case ${1:-} in
list) jq -r '.[] | "\(.ip)\t\(.name)"' "$peers" ;;
add) [ $# -ge 2 ] && [ $# -le 3 ] || usage; add "$2" "${3:-}" ;;
conf)
  [ $# -ge 2 ] && [ $# -le 3 ] || usage
  c=$(conf "$2") || exit 1
  if [ $# -eq 3 ]; then
    out=$3
    [[ $out == /* ]] || out=$here/$out
    umask 077
    printf '%s\n' "$c" >"$out.tmp"
    mv "$out.tmp" "$out"
    echo "wrote $out"
  else
    printf '%s\n' "$c"
  fi
  ;;
qr)
  [ $# -eq 2 ] || usage
  c=$(conf "$2") || exit 1
  printf '%s\n' "$c" | qrencode -t ansiutf8
  ;;
*) usage ;;
esac
