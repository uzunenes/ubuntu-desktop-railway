# Ubuntu XFCE desktop for Railway.
#
# Wraps the LinuxServer webtop image and fixes the defect that defines this
# category: upstream only enables its nginx basic auth when PASSWORD is a
# non-empty string, so a deploy that leaves the variable blank serves a full
# root-capable XFCE session -- HTTP and the /websocket control channel alike --
# to anyone who loads the URL. This image refuses to start instead.
FROM linuxserver/webtop@sha256:1bd141d5d7aaf3e98e47b7d9665f50657d1628617b4ef47bc3bbd43d726fd77e

# Literals a template variable cannot carry: Railway drops a literal defaultValue at
# templateGenerate time and republishes it as a blank REQUIRED field, so these are baked
# into the image instead of published on the deploy form.
ENV CUSTOM_USER=admin \
    TITLE="Ubuntu Desktop" \
    PUID=1000 \
    PGID=1000 \
    TZ=Etc/UTC \
    START_DOCKER=false

# Railway's HTTP healthcheck is an unauthenticated request, and the whole server is
# behind basic auth once a password is set, so the probe needs one exempt location.
# Patched into the shipped template at BUILD time -- the alternative is a sed inside a
# start command, which is re-run against a moving upstream file on every boot.
RUN sed -i 's|^  listen \[::\]:3000 default_server;|  listen [::]:3000 default_server;\n  location = /healthz { auth_basic off; return 200 "ok"; }|' /defaults/default.conf \
 && grep -q 'healthz' /defaults/default.conf

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

# Railway mounts the volume as uid 0 and the image's own init-adduser repairs /config
# for PUID/PGID, which it can only do as root. Making root the last USER instruction
# does the same job as a RAILWAY_RUN_UID template variable, without publishing one.
USER root

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
