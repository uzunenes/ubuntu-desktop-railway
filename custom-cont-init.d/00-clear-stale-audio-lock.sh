#!/bin/bash
# svc-selkies (root/etc/s6-overlay/s6-rc.d/svc-selkies/run in
# linuxserver/docker-baseimage-selkies) only (re)creates the "output" and
# "input" PulseAudio null-sinks when /dev/shm/audio.lock is absent -- see
# linuxserver/docker-baseimage-selkies issue #191. If that file is already
# present when the container boots, the sinks are silently skipped: no
# "output" sink means no "output.monitor" source, so pcmflux (audio capture)
# fails and the desktop has no sound at all.
#
# /dev/shm is meant to be reset on every fresh container, but has been
# observed with a stale lock still present at boot on this deployment.
# Clearing it here, before services start (this runs from
# /custom-cont-init.d, the officially supported pre-service init hook),
# guarantees the null-sinks get (re)created on every boot regardless.
rm -f /dev/shm/audio.lock
