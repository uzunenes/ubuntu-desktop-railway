#!/usr/bin/env python3
"""Backport of upstream selkies' reconnect grace period into the older
monolithic selkies.py that linuxserver/docker-baseimage-selkies still pins
(commit 348bc4f6, 2026-08-05 -- predates selkies-project/selkies's split of
this file into websockets_mode.py and the introduction of RECONNECT_GRACE_S).

Bug being fixed: on disconnect, the data-websocket handler immediately does
`del self.display_clients[display_id]` and reconfigures. A reconnecting
client that lands in that same instant registers as a brand new entry with
width=0/height=0 (real dimensions only arrive with its first SETTINGS
message). If a reconfiguration races in during that window, total display
size computes to zero, the reconfiguration is aborted, and the client is
sent VIDEO_STOPPED -- producing a stuck "Waiting for stream" screen until a
fresh page load. This is the "Calculated total display size is zero.
Aborting reconfiguration." error seen in production logs.

Fix: instead of tearing the display down immediately, wait a short grace
period. If the same display_id is reclaimed by a new connection within that
window, it takes the existing "Client is taking over existing display"
branch (which reuses the entry and preserves width/height) instead of the
"Registering new client" branch (which resets to 0/0) -- eliminating the
race entirely, mirroring upstream's own fix.
"""
import glob
import sys

CANDIDATES = glob.glob("/lsiopy/lib/python3.*/site-packages/selkies/selkies.py")
if len(CANDIDATES) != 1:
    sys.exit(
        f"[fix_reconnect_teardown_race] expected exactly one selkies.py under /lsiopy, "
        f"found {CANDIDATES!r}"
    )

TARGET = CANDIDATES[0]

OLD_BLOCK = '''            if disconnected_display_id:
                del self.display_clients[disconnected_display_id]
                data_logger.info(f"Client for '{disconnected_display_id}' disconnected. Removing and triggering full display reconfiguration.")
                await self.reconfigure_displays()
            else:
                data_logger.info(f"Unregistered client at {raddr} disconnected. No display reconfiguration needed.")'''

NEW_BLOCK = '''            if disconnected_display_id:
                data_logger.info(
                    f"Client for '{disconnected_display_id}' disconnected. "
                    "Deferring display teardown by 3s in case of a quick reconnect."
                )

                async def _teardown_if_unclaimed(_did=disconnected_display_id, _dead_ws=websocket):
                    await asyncio.sleep(3.0)
                    _entry = self.display_clients.get(_did)
                    if _entry is None or _entry.get('ws') is not _dead_ws:
                        data_logger.info(
                            f"Display '{_did}' was reclaimed by a new connection during the "
                            "grace period; skipping teardown."
                        )
                        return
                    del self.display_clients[_did]
                    data_logger.info(
                        f"Client for '{_did}' did not return within the grace period. "
                        "Removing and triggering full display reconfiguration."
                    )
                    await self.reconfigure_displays()

                if not hasattr(self, '_reconnect_grace_tasks'):
                    self._reconnect_grace_tasks = set()
                _grace_task = asyncio.create_task(_teardown_if_unclaimed())
                self._reconnect_grace_tasks.add(_grace_task)
                _grace_task.add_done_callback(self._reconnect_grace_tasks.discard)
            else:
                data_logger.info(f"Unregistered client at {raddr} disconnected. No display reconfiguration needed.")'''

with open(TARGET, "r", encoding="utf-8") as f:
    content = f.read()

count = content.count(OLD_BLOCK)
if count != 1:
    sys.exit(
        f"[fix_reconnect_teardown_race] expected exactly one match of the disconnect-handling "
        f"block in {TARGET}, found {count}. Upstream code likely changed; patch needs updating."
    )

content = content.replace(OLD_BLOCK, NEW_BLOCK)

with open(TARGET, "w", encoding="utf-8") as f:
    f.write(content)

print(f"[fix_reconnect_teardown_race] patched {TARGET}")
