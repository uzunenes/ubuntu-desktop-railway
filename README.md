# ubuntu-desktop-railway

A Railway wrapper around [`linuxserver/webtop:ubuntu-xfce`](https://docs.linuxserver.io/images/docker-webtop/) —
a full Ubuntu XFCE desktop streamed to the browser over a single HTTP port.

## What this image changes

1. **It refuses to boot without a password.** Upstream enables its nginx basic
   auth only inside `if [ -n "${PASSWORD}" ]`
   (`/etc/s6-overlay/s6-rc.d/init-nginx/run`); the `auth_basic` directives in
   `/defaults/default.conf` are shipped commented out and are only uncommented
   when the variable is non-empty. A blank value therefore does not weaken the
   desktop, it publishes it — the HTML client, and the `/websocket` control
   channel that carries keyboard and mouse input, both answer anonymous
   requests. This entrypoint exits 1 with an explanatory message instead.
2. **It honours the injected `$PORT`.** webtop reads `CUSTOM_PORT`, not `PORT`,
   and Railway's HTTP healthcheck dials the port it injected rather than the
   domain's target port. The entrypoint exports `CUSTOM_PORT="${PORT:-3000}"`.
3. **It bakes the healthcheck exemption at build time.** The whole server sits
   behind basic auth once a password is set, so the unauthenticated probe needs
   one exempt location. `/healthz` is patched into
   `/defaults/default.conf` in a build layer, with a `grep` assertion, so an
   upstream change to that file fails the build rather than silently shipping a
   template whose healthcheck cannot pass.
4. **It pins the base image by digest** and bakes the literals a Railway
   template variable cannot carry (`CUSTOM_USER`, `TITLE`, `PUID`, `PGID`,
   `TZ`, `START_DOCKER`), so the deploy form publishes one variable and no
   blank required fields.

## Variables

| Name | Required | Notes |
| --- | --- | --- |
| `PASSWORD` | yes | Basic-auth password for user `admin`. Empty value refuses to boot. |

## Volume

Mount at `/config` — it is the desktop user's home directory.
