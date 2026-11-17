#!/usr/bin/env bash
set -euo pipefail
umask 022

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/common.sh
source "$project_dir/scripts/common.sh"

preflight() {
    local ID='' VERSION_ID=''
    # shellcheck source=/dev/null
    source /etc/os-release
    [[ $ID == ubuntu && $VERSION_ID == 24.04 ]] || die 'Use Ubuntu Server 24.04 LTS.'
    [[ $(uname -m) == aarch64 && $(dpkg --print-architecture) == arm64 ]] ||
        die 'Use a imagem Ubuntu ARM64 em VM.Standard.A1.Flex.'
    [[ -d /run/systemd/system ]] || die 'Execute em uma VM Ubuntu inicializada com systemd.'
    [[ $(stat -fc %T /sys/fs/cgroup) == cgroup2fs ]] || die 'O sistema precisa de cgroup v2.'
}

prepare_user() {
    local account=$1 entry name uid gid comment home shell group
    if getent passwd "$account" >/dev/null; then
        entry=$(getent passwd "$account")
        IFS=: read -r name _ uid gid comment home shell <<< "$entry"
        group=$(getent group "$gid")
        [[ $name == "$account" && $uid -ge 1000 && $comment == 'PokeIdle Cloud' &&
           $home == "/home/$account" && $shell == /usr/sbin/nologin &&
           ${group%%:*} == "$account" && -d $home && ! -L $home &&
           $(stat -c %u "$home") == "$uid" ]] || die "Conta existente incompatível: $account"
    else
        useradd -m -U -s /usr/sbin/nologin -c 'PokeIdle Cloud' "$account"
        uid=$(id -u "$account")
        home="/home/$account"
    fi
    chmod 0700 "$home"
    loginctl enable-linger "$account"
    systemctl start "user@$uid.service"
}

case ${1:-} in
    --help|-h)
        printf 'Uso: %s [--check]\n' "${0##*/}"
        exit 0
        ;;
    --check)
        [[ $# == 1 ]] || die 'Uso: install.sh --check'
        preflight
        printf 'Ubuntu 24.04 ARM64, systemd e cgroup v2 detectados.\n'
        exit 0
        ;;
    '') [[ $# == 0 ]] || die 'Uso: install.sh [--check]' ;;
    *) die 'Uso: install.sh [--check]' ;;
esac

require_root
preflight
exec 9>/run/pokeidle-cloud-install.lock
flock -n 9 || die 'Outra instalação está em execução.'
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl dbus-user-session fonts-dejavu-core iproute2 procps python3 snapd \
    thunar tigervnc-standalone-server tigervnc-tools xauth x11-utils x11-xserver-utils \
    xfce4-panel xfce4-session xfce4-settings xfconf xfdesktop4 xfwm4

if ! dpkg-query -W -f='${Status}' tailscale 2>/dev/null | grep -qx 'install ok installed'; then
    temp_dir=$(mktemp -d)
    trap 'rm -rf -- "$temp_dir"' EXIT
    repo=https://pkgs.tailscale.com/stable/ubuntu
    curl --fail --silent --show-error --location --proto '=https' --retry 3 \
        --connect-timeout 15 --max-time 90 "$repo/noble.noarmor.gpg" -o "$temp_dir/tailscale.gpg"
    install -m 0644 "$temp_dir/tailscale.gpg" /usr/share/keyrings/tailscale-archive-keyring.gpg
    printf 'deb [arch=arm64 signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] %s noble main\n' "$repo" \
        > "$temp_dir/tailscale.list"
    install -m 0644 "$temp_dir/tailscale.list" /etc/apt/sources.list.d/tailscale.list
    apt-get update
    apt-get install -y --no-install-recommends tailscale
fi

systemctl enable --now snapd.socket tailscaled.service
timeout 180 snap wait system seed.loaded
if ! snap list chromium >/dev/null 2>&1; then
    snap install chromium --channel=latest/stable
fi
systemd-tmpfiles --create --prefix=/tmp/.X11-unix --prefix=/tmp/.ICE-unix

prepare_user pokeidle-1
prepare_user pokeidle-2
install -d -m 0755 /usr/local/lib/pokeidle-cloud /usr/local/sbin
install -m 0644 "$project_dir/scripts/common.sh" /usr/local/lib/pokeidle-cloud/
install -m 0755 "$project_dir/scripts/session.sh" /usr/local/lib/pokeidle-cloud/
for name in access doctor recover; do
    install -m 0755 "$project_dir/scripts/$name.sh" "/usr/local/sbin/pokeidle-$name"
done
install -m 0644 "$project_dir/systemd/pokeidle-session@.service" /etc/systemd/system/
systemctl daemon-reload

printf '%s\n' 'Instalação concluída. Siga o README para criar as senhas VNC, iniciar as sessões e conectar ao Tailscale.'
