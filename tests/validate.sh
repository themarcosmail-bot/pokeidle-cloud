#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

for script in install.sh scripts/*.sh tests/*.sh; do
    bash -n "$script"
done
./install.sh --help >/dev/null
if ./install.sh --invalid >/dev/null 2>&1; then
    printf 'O instalador aceitou uma opção inválida.\n' >&2
    exit 1
fi
printf 'Sintaxe Bash e opções do instalador: OK\n'

temp_dir=$(mktemp -d)
trap 'rm -rf -- "$temp_dir"' EXIT
sed "s|ExecStart=/usr/local/lib/pokeidle-cloud/session.sh|ExecStart=\"$PWD/scripts/session.sh\"|" \
    systemd/pokeidle-session@.service > "$temp_dir/pokeidle-session@.service"
ln -s pokeidle-session@.service "$temp_dir/pokeidle-session@1.service"
ln -s pokeidle-session@.service "$temp_dir/pokeidle-session@2.service"
systemd-analyze verify --man=no "$temp_dir/pokeidle-session@1.service" "$temp_dir/pokeidle-session@2.service"
printf 'Unidades systemd para as duas sessões: OK\n'

python3 tests/test_scripts.py
