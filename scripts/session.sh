#!/usr/bin/env bash
set -euo pipefail
umask 077

# shellcheck source=common.sh
source "${BASH_SOURCE[0]%/*}/common.sh"
select_session "${1:-}"
[[ $EUID != 0 && $(id -un) == "$session_user" ]] ||
    die "A sessão deve usar o usuário $session_user."

export HOME="$session_home"
export XDG_RUNTIME_DIR="/run/user/$EUID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
export DISPLAY="$session_display" XAUTHORITY="$XDG_RUNTIME_DIR/.Xauthority"
export XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=XFCE
unset SESSION_MANAGER WAYLAND_DISPLAY

vnc_password="$HOME/.vnc/passwd"
[[ -s $vnc_password && ! -L $vnc_password && -O $vnc_password &&
    $(stat -c %a "$vnc_password") == 600 ]] ||
    die "Defina uma senha com sudo pokeidle-access password $session_id."

# O serviço de usuário com linger pode ainda estar subindo após um boot.
for ((attempt = 0; attempt < 30; attempt++)); do
    [[ -S $XDG_RUNTIME_DIR/bus ]] && break
    sleep 1
done
[[ -S $XDG_RUNTIME_DIR/bus ]] || die "D-Bus indisponível em $XDG_RUNTIME_DIR."

state_dir="$XDG_RUNTIME_DIR/pokeidle-cloud"
install -d -m 0700 "$state_dir"
rm -f -- "$state_dir/chromium.pid"
touch "$XAUTHORITY"
chmod 0600 "$XAUTHORITY"
printf 'add %s MIT-MAGIC-COOKIE-1 %s\n' "$DISPLAY" "$(mcookie)" | xauth -q -f "$XAUTHORITY"

browser_worker='' xfce_pid='' vnc_pid='' health_wait=''

cleanup() {
    if [[ -n $health_wait ]]; then
        kill -TERM "$health_wait" 2>/dev/null || true
    fi
    if [[ -n $browser_worker ]]; then
        kill -TERM "$browser_worker" 2>/dev/null || true
        wait "$browser_worker" 2>/dev/null || true
    fi
    if [[ -n $xfce_pid ]]; then
        kill -TERM "$xfce_pid" 2>/dev/null || true
    fi
    if [[ -n $vnc_pid ]]; then
        kill -TERM "$vnc_pid" 2>/dev/null || true
    fi
    if [[ -n $xfce_pid ]]; then
        wait "$xfce_pid" 2>/dev/null || true
    fi
    if [[ -n $vnc_pid ]]; then
        wait "$vnc_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 0' TERM INT

Xtigervnc "$DISPLAY" -auth "$XAUTHORITY" -nolisten tcp -noreset \
    -geometry 1280x800 -depth 24 -rfbport "$session_port" -localhost \
    -SecurityTypes VncAuth -PasswordFile "$vnc_password" -AlwaysShared &
vnc_pid=$!

x_ready=false
for ((attempt = 0; attempt < 30; attempt++)); do
    kill -0 "$vnc_pid" 2>/dev/null || die 'TigerVNC encerrou durante a inicialização.'
    if timeout 2s xdpyinfo >/dev/null 2>&1; then
        x_ready=true
        break
    fi
    sleep 1
done
[[ $x_ready == true ]] || die 'O display X11 não respondeu.'

dbus-update-activation-environment --systemd DISPLAY XAUTHORITY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP
xset s off
xset s noblank
xfconf-query -c xfwm4 -p /general/use_compositing --create -t bool -s false
xfconf-query -c xfce4-session -p /general/SaveOnExit --create -t bool -s false

startxfce4 &
xfce_pid=$!

run_browser() {
    local pid='' retry_pid='' failures=0 started status
    local profile="$HOME/snap/chromium/common/pokeidle-profile"
    trap 'rm -f -- "$state_dir/chromium.pid"' EXIT
    # O Snap pode realocar o processo do Chromium para um escopo systemd do usuário.
    trap '
        if [[ -n $pid ]]; then
            kill -TERM "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
        if [[ -n $retry_pid ]]; then
            kill -TERM "$retry_pid" 2>/dev/null || true
        fi
        exit 0
    ' TERM INT
    install -d -m 0700 "$profile"
    while :; do
        started=$SECONDS
        /snap/bin/chromium --user-data-dir="$profile" --ozone-platform=x11 \
            --no-first-run --no-default-browser-check --start-maximized \
            https://pokeidle.io/ &
        pid=$!
        printf '%s\n' "$pid" > "$state_dir/chromium.pid"

        status=0
        wait "$pid" || status=$?
        pid=''
        rm -f -- "$state_dir/chromium.pid"
        if (( status == 0 )); then
            printf 'O Chromium encerrou normalmente. O desktop continua disponível.\n'
            exit 0
        fi

        if (( SECONDS - started >= 120 )); then
            failures=0
        fi
        failures=$((failures + 1))
        if (( failures >= 3 )); then
            die "Chromium encerrou repetidamente (código $status). Consulte o journal e execute pokeidle-recover $session_id."
        fi

        printf 'Chromium encerrou com código %s. Reiniciando em 15 segundos.\n' "$status" >&2
        sleep 15 &
        retry_pid=$!
        wait "$retry_pid"
        retry_pid=''
    done
}
run_browser &
browser_worker=$!

# Uma saída de X11 ou XFCE reconstrói o desktop inteiro pelo systemd.
while kill -0 "$vnc_pid" 2>/dev/null && kill -0 "$xfce_pid" 2>/dev/null; do
    sleep 5 &
    health_wait=$!
    wait "$health_wait"
    health_wait=''
done
die 'O servidor gráfico ou a sessão XFCE encerrou.'
