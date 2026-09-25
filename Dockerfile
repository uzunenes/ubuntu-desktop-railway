# Ubuntu XFCE desktop for Railway.
#
# Wraps the LinuxServer webtop image and fixes the defect that defines this
# category: upstream only enables its nginx basic auth when PASSWORD is a
# non-empty string, so a deploy that leaves the variable blank serves a full
# root-capable XFCE session -- HTTP and the /websocket control channel alike --
# to anyone who loads the URL. This image refuses to start instead.
FROM lscr.io/linuxserver/webtop:ubuntu-xfce

# Literals a template variable cannot carry: Railway drops a literal defaultValue at
# templateGenerate time and republishes it as a blank REQUIRED field, so these are baked
# into the image instead of published on the deploy form.
#
# SELKIES_JPEG_QUALITY overrides the pinned selkies commit's default of 40, which is only
# used while the screen is actively changing (idle frames already get a quality-90
# "paint-over"), producing visibly blocky/blurry video during any motion. 80 is a still-
# CPU-friendly middle ground for this software-encoded (no GPU on Railway) deployment; set
# a Railway service variable of the same name to override it per-deploy.
ENV CUSTOM_USER=admin \
    TITLE="Ubuntu Desktop" \
    PUID=1000 \
    PGID=1000 \
    TZ=Etc/UTC \
    START_DOCKER=false \
    SELKIES_JPEG_QUALITY=80

# Railway's HTTP healthcheck is an unauthenticated request, and the whole server is
# behind basic auth once a password is set, so the probe needs one exempt location.
# Patched into the shipped template at BUILD time -- the alternative is a sed inside a
# start command, which is re-run against a moving upstream file on every boot.
RUN sed -i 's|^  listen \[::\]:3000 default_server;|  listen [::]:3000 default_server;\n  location = /healthz { auth_basic off; return 200 "ok"; }|' /defaults/default.conf \
 && grep -q 'healthz' /defaults/default.conf

# The selkies commit this image pins (348bc4f6, 2026-08-05) predates upstream's own fix
# for a reconnect race: on disconnect it tears the display down immediately, so a client
# that reconnects in that same instant re-registers with width=0/height=0 until its next
# SETTINGS message. If a reconfiguration lands in that window, the computed display size
# is zero, the reconfiguration aborts, and the client is stuck on "Waiting for stream"
# until a full page reload. This backports a grace period so a quick reconnect reclaims
# the existing display entry instead of racing a fresh, dimensionless one.
COPY patches/fix_reconnect_teardown_race.py /tmp/fix_reconnect_teardown_race.py
RUN /lsiopy/bin/python3 /tmp/fix_reconnect_teardown_race.py && rm /tmp/fix_reconnect_teardown_race.py

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

# svc-selkies only (re)creates the "output"/"input" PulseAudio null-sinks when
# /dev/shm/audio.lock is absent (linuxserver/docker-baseimage-selkies issue #191). A stale
# lock left over at boot silently skips sink creation, so pcmflux never finds
# "output.monitor" and the desktop has no audio. /custom-cont-init.d is the officially
# supported hook that runs, as root, before services start on every boot.
COPY custom-cont-init.d/00-clear-stale-audio-lock.sh /custom-cont-init.d/00-clear-stale-audio-lock.sh
RUN chmod +x /custom-cont-init.d/00-clear-stale-audio-lock.sh

# Railway mounts the volume as uid 0 and the image's own init-adduser repairs /config
# for PUID/PGID, which it can only do as root. Making root the last USER instruction
# does the same job as a RAILWAY_RUN_UID template variable, without publishing one.
USER root

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
