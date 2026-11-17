#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

fail() {
    printf 'Falha de segurança: %s\n' "$*" >&2
    exit 1
}

require_literal() {
    local file=$1 literal=$2 description=$3
    grep -Fq -- "$literal" "$file" || fail "$description"
}

forbidden_regex='(--remote-debugging-port|--remote-debugging-pipe|--enable-automation|selenium|puppeteer|playwright)'
if grep -RInE -- "$forbidden_regex" install.sh scripts systemd .github 2>/dev/null; then
    fail 'foram encontradas flags ou ferramentas de automação de navegador'
fi

if grep -RInE -- 'tailscale[[:space:]]+funnel' install.sh scripts systemd .github 2>/dev/null; then
    fail 'Tailscale Funnel não deve ser habilitado'
fi

if grep -RInE -- '(BEGIN (OPENSSH|RSA|EC) PRIVATE KEY|tskey-(auth|client)-[A-Za-z0-9_-]+)'     install.sh scripts systemd .github 2>/dev/null; then
    fail 'material de credencial ou chave privada detectado'
fi

require_literal scripts/session.sh '-localhost'     'TigerVNC deve permanecer restrito a loopback'
require_literal scripts/session.sh '-nolisten tcp'     'o servidor X11 não deve aceitar conexões TCP'
require_literal scripts/session.sh '-SecurityTypes VncAuth'     'a autenticação VNC deve permanecer habilitada'
require_literal scripts/access.sh 'tcp://127.0.0.1:'     'Tailscale Serve deve encaminhar apenas para loopback'
require_literal install.sh "--proto '=https'"     'downloads do instalador devem restringir curl a HTTPS'
require_literal systemd/pokeidle-session@.service 'UMask=0077'     'a unidade deve manter uma umask restritiva'

if grep -Eqi -- '(Cookies|Login Data|Web Data|History|Local State)' scripts/chromium-health.sh; then
    fail 'o health check não deve ler bancos de credenciais ou histórico do Chromium'
fi

printf 'Verificações básicas de segurança: OK\n'
