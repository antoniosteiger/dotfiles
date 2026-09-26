#!/usr/bin/env bash
# Report how heavy this NixOS config is.
#   ./tools/weigh.sh              # weigh the running system
#   ./tools/weigh.sh lenovo_t14s_gen2   # weigh a host from the flake (builds if needed)
set -euo pipefail

TOP="${1:-/run/current-system}"
if [ "$TOP" != "/run/current-system" ]; then
  echo "building .#${TOP} ..." >&2
  TOP=$(nix build --no-link --print-out-paths ".#nixosConfigurations.${TOP}.config.system.build.toplevel")
fi

printf '\n== closure ==\n'
nix path-info -Sh "$TOP" | awk '{printf "  total closure   %s %s\n", $2, $3}'
nix path-info -r "$TOP" | wc -l | awk '{printf "  store paths     %s\n", $1}'
du -sh /nix/store 2>/dev/null | awk '{printf "  /nix/store      %s  (all generations)\n", $1}'

printf '\n== heaviest packages (own size, not closure) ==\n'
nix path-info -r "$TOP" | xargs du -sb 2>/dev/null | sort -rn | head -25 |
  awk '{n=$2; sub(/^\/nix\/store\/[a-z0-9]+-/,"",n); printf "  %7.0f MiB  %s\n", $1/1048576, n}'

printf '\n== boot ==\n'
systemd-analyze 2>/dev/null | head -1 | sed 's/^/  /'

printf '\n== idle RAM by component ==\n'
ps -eo rss,comm --no-headers | awk '
  { rss[$2]+=$1 }
  END { for (c in rss) printf "%d %s\n", rss[c], c }' | sort -rn | head -15 |
  awk '{printf "  %6.0f MiB  %s\n", $1/1024, $2}'
free -m | awk '/^Mem:/ {printf "\n  used %s MiB of %s MiB\n", $3, $2}'
