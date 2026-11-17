#!/usr/bin/env bash

die() {
    printf 'Erro: %s\n' "$*" >&2
    exit 1
}

require_root() {
    [[ $EUID == 0 ]] || die 'Execute com sudo.'
}

select_session() {
    case ${1:-} in
        1|2) ;;
        *) die 'A sessão deve ser 1 ou 2.' ;;
    esac
    session_id=$1
    session_user="pokeidle-$session_id"
    session_port=$((5900 + session_id))
    session_display=:$((70 + session_id))
    session_home="/home/$session_user"
    session_unit="pokeidle-session@$session_id.service"
}

# Aceita apenas um backend que escute em loopback e tenha IPv4 configurado.
loopback_only() {
    local port=$1 listeners
    listeners=$(ss -H -ltn "sport = :$port") || return 1
    awk -v port="$port" '
        $4 == "127.0.0.1:" port { ipv4 = 1 }
        $4 != "127.0.0.1:" port && $4 != "[::1]:" port { exposed = 1 }
        END { exit !(ipv4 && !exposed) }
    ' <<< "$listeners"
}
