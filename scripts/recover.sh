#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common.sh
source /usr/local/lib/pokeidle-cloud/common.sh
[[ $# == 1 ]] || die 'Uso: pokeidle-recover {1|2|all}'
if [[ $1 == --help || $1 == -h ]]; then
    printf 'Uso: pokeidle-recover {1|2|all}\n'
    exit 0
fi
require_root

sessions=(1 2)
if [[ $1 != all ]]; then
    select_session "$1"
    sessions=("$session_id")
fi

result=0
for id in "${sessions[@]}"; do
    select_session "$id"
    printf 'Reiniciando a sessão %s. O perfil em disco será preservado.\n' "$id"
    # O reset é útil após o limite de partidas do systemd ser alcançado.
    systemctl reset-failed "$session_unit" 2>/dev/null || true
    if ! systemctl restart "$session_unit"; then
        printf 'Consulte: sudo journalctl -u %s -n 80 --no-pager\n' "$session_unit" >&2
        result=1
        continue
    fi

    ready=false
    for ((attempt = 0; attempt < 45; attempt++)); do
        if systemctl is-active --quiet "$session_unit" && loopback_only "$session_port"; then
            ready=true
            break
        fi
        sleep 1
    done
    if [[ $ready == true ]]; then
        printf 'VNC local da sessão %s disponível. Use sudo pokeidle-doctor %s para inspecionar o Chromium.\n' "$id" "$id"
    else
        printf 'Sessão %s sem VNC local após 45 segundos. Consulte: sudo journalctl -u %s -n 80 --no-pager\n' "$id" "$session_unit" >&2
        result=1
    fi
done
exit "$result"
