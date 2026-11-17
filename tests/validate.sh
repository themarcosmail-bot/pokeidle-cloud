#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

validate_bash() {
    for script in install.sh scripts/*.sh tests/*.sh; do
        bash -n "$script"
    done
    ./install.sh --help >/dev/null
    if ./install.sh --invalid >/dev/null 2>&1; then
        printf 'O instalador aceitou uma opção inválida.\n' >&2
        return 1
    fi
    printf 'Sintaxe Bash e opções do instalador: OK\n'
}

validate_systemd() {
    local temp_dir current_user current_group
    temp_dir=$(mktemp -d)
    trap 'rm -rf -- "$temp_dir"' RETURN
    current_user=$(id -un)
    current_group=$(id -gn)

    sed         -e "s|User=pokeidle-%i|User=$current_user|"         -e "s|Group=pokeidle-%i|Group=$current_group|"         -e "s|WorkingDirectory=/home/pokeidle-%i|WorkingDirectory=$PWD|"         -e "s|ExecStart=/usr/local/lib/pokeidle-cloud/session.sh|ExecStart=$PWD/scripts/session.sh|"         systemd/pokeidle-session@.service > "$temp_dir/pokeidle-session@.service"

    ln -s pokeidle-session@.service "$temp_dir/pokeidle-session@1.service"
    ln -s pokeidle-session@.service "$temp_dir/pokeidle-session@2.service"
    systemd-analyze verify --man=no         "$temp_dir/pokeidle-session@1.service"         "$temp_dir/pokeidle-session@2.service"
    printf 'Unidades systemd para as duas sessões: OK\n'
}

validate_python() {
    python3 tests/test_scripts.py
}

case ${1:-all} in
    bash) validate_bash ;;
    systemd) validate_systemd ;;
    python) validate_python ;;
    all)
        validate_bash
        validate_systemd
        validate_python
        ;;
    *)
        printf 'Uso: %s [bash|systemd|python|all]\n' "${0##*/}" >&2
        exit 2
        ;;
esac
