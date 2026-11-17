#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Uso: %s <usuario> <arquivo-pid> <perfil-esperado>\n' "${0##*/}"
}

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    usage
    exit 0
fi
[[ $# == 3 ]] || {
    usage >&2
    exit 2
}

session_user=$1
pid_file=$2
expected_profile=$3

entry=$(getent passwd "$session_user") || fail "usuário inexistente: $session_user"
IFS=: read -r _ _ uid _ _ home _ <<< "$entry"
[[ $uid =~ ^[0-9]+$ ]] || fail "UID inválido para $session_user"
[[ -n $home && $home == /* ]] || fail "home inválida para $session_user"

[[ -f $pid_file && ! -L $pid_file ]] || fail 'arquivo PID ausente, inválido ou simbólico'
[[ $(stat -c %u "$pid_file" 2>/dev/null) == "$uid" ]] || fail 'arquivo PID pertence a outro usuário'
[[ $(stat -c %a "$pid_file" 2>/dev/null) == 600 ]] || fail 'arquivo PID precisa usar modo 600'

pid=$(cat -- "$pid_file" 2>/dev/null) || fail 'não foi possível ler o arquivo PID'
[[ $pid =~ ^[1-9][0-9]*$ ]] || fail 'PID inválido'

proc_dir="/proc/$pid"
[[ -d $proc_dir ]] || fail "processo $pid ausente"
[[ $(stat -c %u "$proc_dir" 2>/dev/null) == "$uid" ]] || fail 'processo pertence a outro usuário'
kill -0 "$pid" 2>/dev/null || fail "processo $pid não está acessível"

proc_stat=$(cat -- "$proc_dir/stat" 2>/dev/null) || fail 'não foi possível ler o estado do processo'
state_tail=${proc_stat##*) }
state=${state_tail%% *}
case $state in
    Z|X|x) fail "processo $pid em estado inválido: $state" ;;
    '') fail 'estado do processo indisponível' ;;
esac

argv=()
while IFS= read -r -d '' arg; do
    argv+=("$arg")
done < "$proc_dir/cmdline"

(("${#argv[@]}" > 0)) || fail 'linha de comando do processo indisponível'

browser_seen=false
profile_seen=false
for arg in "${argv[@]}"; do
    case $arg in
        *chromium*|*chrome*) browser_seen=true ;;
    esac
    [[ $arg == "--user-data-dir=$expected_profile" ]] && profile_seen=true
done

[[ $browser_seen == true ]] || fail 'o PID não corresponde a um processo Chromium'
[[ $profile_seen == true ]] || fail 'o Chromium não usa o perfil esperado'

printf 'processo íntegro (PID %s, estado %s)\n' "$pid" "$state"
