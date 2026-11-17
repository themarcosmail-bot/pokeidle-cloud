#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common.sh
source /usr/local/lib/pokeidle-cloud/common.sh
[[ $# -le 1 ]] || die 'Uso: pokeidle-doctor [1|2]'
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf 'Uso: pokeidle-doctor [1|2]\n'
    exit 0
fi
require_root

sessions=(1 2)
if [[ $# == 1 ]]; then
    select_session "$1"
    sessions=("$session_id")
fi

failed=0
for id in "${sessions[@]}"; do
    select_session "$id"
    printf '\nSessão %s (%s, VNC %s)\n' "$session_id" "$session_display" "$session_port"

    if systemctl is-active --quiet "$session_unit"; then
        printf '  systemd: ativo\n'
    else
        printf '  systemd: inativo ou com falha\n'
        failed=1
    fi
    if loopback_only "$session_port"; then
        printf '  VNC: restrito a loopback\n'
    else
        printf '  VNC: ausente ou endereço de escuta inesperado\n'
        failed=1
    fi

    if uid=$(getent passwd "$session_user" | cut -d: -f3) && [[ $uid =~ ^[0-9]+$ ]]; then
        pid_file="/run/user/$uid/pokeidle-cloud/chromium.pid"
        if pid=$(timeout 2s runuser -u "$session_user" -- sh -c '[ -f "$1" ] && [ ! -L "$1" ] && cat "$1"' sh "$pid_file" 2>/dev/null) &&
           [[ $pid =~ ^[1-9][0-9]*$ ]] &&
           [[ $(stat -c %u "/proc/$pid" 2>/dev/null) == "$uid" ]] &&
           kill -0 "$pid" 2>/dev/null; then
            printf '  Chromium: processo vivo (PID %s)\n' "$pid"
            continue
        fi
    fi
    printf '  Chromium: ausente ou em reinicialização\n'
    failed=1
done

printf '\nTailscale\n'
if ip=$(tailscale ip -4 2>/dev/null); then
    printf '  IPv4 privado: %s\n' "$ip"
    ports=()
    for id in "${sessions[@]}"; do
        select_session "$id"
        ports+=("$session_port")
    done
    if ! tailscale serve status --json | python3 -c '
import json
import sys

try:
    config = json.load(sys.stdin) or {}
except ValueError:
    print("  Configuração do Serve indisponível.")
    sys.exit(1)

failed = False
for port in sys.argv[1:]:
    route = config.get("TCP", {}).get(port, {})
    valid = route.get("TCPForward") == f"127.0.0.1:{port}"
    if valid and not route.get("TerminateTLS") and not route.get("ProxyProtocol"):
        print(f"  TCP {port}: encaminhamento privado configurado")
    else:
        print(f"  TCP {port}: encaminhamento privado ausente ou diferente do esperado")
        failed = True
sys.exit(failed)
' "${ports[@]}"; then
        failed=1
    fi
else
    printf '  Sem IPv4 Tailscale. Verifique a conexão do dispositivo.\n'
    failed=1
fi
printf '\nMemória\n'
free -h
printf '\nDisco do sistema\n'
df -h /
printf '\nCarga da VM\n'
uptime

exit "$failed"
