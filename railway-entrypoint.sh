#!/bin/bash
set -euo pipefail

# 1. Fail closed on a missing password.
#
# linuxserver/webtop enables nginx basic auth only inside
# `if [ -n "${PASSWORD}" ]` (/etc/s6-overlay/s6-rc.d/init-nginx/run); the
# auth_basic directives in /defaults/default.conf stay commented out otherwise.
# An empty value therefore does not weaken the desktop, it publishes it. A dead
# deploy is the correct failure mode for that, so refuse to boot.
if [ -z "${PASSWORD:-}" ]; then
  echo "[railway] FATAL: PASSWORD is empty." >&2
  echo "[railway] The desktop is protected by nginx basic auth, which upstream only" >&2
  echo "[railway] enables when PASSWORD is set. Booting without it would serve a root" >&2
  echo "[railway] XFCE session to anyone with this URL. Set PASSWORD and redeploy." >&2
  exit 1
fi

# 2. Honour the injected port.
#
# webtop reads CUSTOM_PORT, not PORT. Railway's healthcheck dials the port it
# injected rather than the domain's target port, so the listener has to follow it.
export CUSTOM_PORT="${PORT:-3000}"
echo "[railway] serving desktop on port ${CUSTOM_PORT}"

exec /init "$@"
