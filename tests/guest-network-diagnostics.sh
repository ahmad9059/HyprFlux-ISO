#!/bin/bash
# VM-only, read-only network probes. Completion means evidence collected, not
# successful connectivity and not an installed-desktop acceptance result.
set -euo pipefail
[[ $(systemd-detect-virt) == qemu || $(systemd-detect-virt) == kvm ]]
printf '\n=== Resolver ===\n'
cat /etc/resolv.conf
ip -brief address
ip route
ip -6 route
for host in geo.mirror.pkgbuild.com mirrors.mit.edu mirror.rackspace.com; do
    printf '\n=== DNS %s ===\n' "$host"
    timeout 10 getent ahosts "$host" || printf 'DNS_LOOKUP_FAILED=%s\n' "$?"
done
for family in auto 4; do
    options=()
    [[ "$family" == 4 ]] && options=(-4)
    for url in \
        https://geo.mirror.pkgbuild.com/core/os/x86_64/core.db \
        https://mirrors.mit.edu/archlinux/core/os/x86_64/core.db \
        https://mirror.rackspace.com/archlinux/core/os/x86_64/core.db; do
        printf '\n=== HTTPS family=%s url=%s ===\n' "$family" "$url"
        curl "${options[@]}" --fail --location --silent --show-error \
            --connect-timeout 8 --max-time 20 --output /dev/null \
            --write-out 'HTTP=%{http_code} peer=%{remote_ip} DNS=%{time_namelookup} total=%{time_total}\n' \
            "$url" || printf 'HTTPS_PROBE_FAILED=%s\n' "$?"
    done
done
printf '\n=== Five concurrent mirror requests ===\n'
pids=()
for ((index=0; index<5; index++)); do
    curl --fail --location --silent --show-error --connect-timeout 8 --max-time 20 \
        --output /dev/null --write-out 'PARALLEL_HTTP=%{http_code} DNS=%{time_namelookup} total=%{time_total}\n' \
        https://geo.mirror.pkgbuild.com/core/os/x86_64/core.db &
    pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid" || printf 'PARALLEL_PROBE_FAILED=%s\n' "$?"; done
echo HYPRFLUX_NETWORK_DIAGNOSTICS_COMPLETE
