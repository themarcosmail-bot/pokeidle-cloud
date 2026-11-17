#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common.sh
source /usr/local/lib/pokeidle-cloud/common.sh

usage() {
    printf 'Uso: pokeidle-access {password 1|password 2|enable [1|2]|disable [1|2]|status}\n'
}

case ${1:-} in
    -h|--help) usage; exit 0 ;;
    password)
        [[ $# == 2 ]] || die 'Especifique a sessão para definir a senha.'
        select_session "$2"
        require_root
        [[ -t 0 ]] || die 'Abra um terminal interativo para definir a senha VNC.'
        printf 'Escolha uma senha VNC exclusiva para a sessão %s com 8 caracteres aleatórios.\n' "$session_id"
        runuser -u "$session_user" -- env HOME="$session_home" bash -c '
            set -euo pipefail
            umask 077
            install -d -m 0700 "$HOME/.vnc"
            tmp_file=$(mktemp "$HOME/.vnc/passwd.XXXXXXXX")
            trap '\''rm -f -- "$tmp_file"'\'' EXIT
            tigervncpasswd "$tmp_file"
            chmod 0600 "$tmp_file"
            mv -fT -- "$tmp_file" "$HOME/.vnc/passwd"
        '
        ;;
    enable|disable)
        [[ $# -le 2 ]] || die 'Selecione 1, 2 ou omita a sessão para aplicar às duas.'
        mode=$1
        sessions=(1 2)
        if [[ $# == 2 ]]; then
            select_session "$2"
            sessions=("$session_id")
        fi
        require_root
        tailscale_ip=$(tailscale ip -4) || die 'Conecte a VM com sudo tailscale up --hostname=pokeidle-cloud.'
        result=0
        if [[ $mode == enable ]]; then
            for id in "${sessions[@]}"; do
                select_session "$id"
                loopback_only "$session_port" || die "Inicie $session_unit e confirme que TCP $session_port está restrita a loopback."
            done
        fi
        for id in "${sessions[@]}"; do
            select_session "$id"
            forwarding=(serve --bg "--tcp=$session_port" "tcp://127.0.0.1:$session_port")
            if [[ $mode == disable ]]; then
                forwarding+=(off)
            fi
            tailscale "${forwarding[@]}" || result=1
        done
        printf 'IPv4 Tailscale: %s\n' "$tailscale_ip"
        tailscale serve status
        exit "$result"
        ;;
    status)
        [[ $# == 1 ]] || die 'Uso: pokeidle-access status'
        tailscale serve status
        ;;
    *) usage >&2; exit 1 ;;
esac
