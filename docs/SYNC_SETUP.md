# Two-device setup — Stage A (S7)

Nimo on two devices (Android phone + Arch Linux laptop), no cloud,
no account. Two separate channels, deliberately (§R7):

| What | How it travels |
|---|---|
| **Library files** (PDFs, TXT, media, quiz packs, HTML quizzes) | A folder-sync tool (Syncthing) mirrors the Library folder |
| **App data** (plans, reviews, streaks, topics, questions…) | **Sync packages**: in the app, Settings → Sync → **Sync now** writes a package into `Library/sync/`; the folder sync carries it; the other device imports it from the same screen (or automatically from the sync folder via Sync now) |
| **Repair / first pairing** | A backup snapshot (Settings → Backup → Export) restored on the other device — guarded (see below) |

**The live database file is never synced.** Not by Syncthing, not
by hand. Record-level packages are the only data channel — a
file-copied SQLite database (db + `-wal` + `-shm` copied
non-atomically) is the classic local-first corruption machine.

---

## 1. Point the app at a shared Library folder

The app stores only *relative* paths, so the Library folder can
live anywhere.

- **Phone:** Settings → Sync → **Change Library folder…** → pick a
  folder in shared storage (e.g. `Internal storage/NimoLibrary`).
  Restart the app. If you already have sources, copy the old
  Library's contents into the new folder first. (The default
  Library is inside app-private storage, which Syncthing cannot
  reach — that's why this step exists.)
  **Android caveat (unverified on-device):** the app probes the
  picked folder by writing a test file before saving the
  setting, and refuses it with an explanation if the write
  fails — under Android's scoped storage a folder picked
  through the system picker may not be writable by the app. If
  your pick is refused, tell the developer path you chose; the
  phone-side route may need an app-specific external folder
  instead. This is the one Stage A step that could not be
  verified without the phone in hand.
- **Laptop:** either let Syncthing sync the app's default Library
  folder (shown on the same Settings → Sync screen), or use
  **Change Library folder…** there too and restart.

## 2. Folder sync (Syncthing)

### Laptop (Arch)

```bash
sudo pacman -S --needed syncthing
systemctl --user enable --now syncthing.service
```

Add the Library folder in the web UI (http://localhost:8384),
share it with the phone.

### Phone

- Install **Syncthing-Fork from F-Droid only** — the official
  Syncthing Android app was discontinued (Dec 2024), and the
  fork's stewardship changed hands in 2025; the F-Droid build is
  built and signed from source by F-Droid. **Pause its
  auto-updates** until the new lineage has a track record (§R7.1).
- Fallback if the fork ever becomes untrustworthy: the upstream
  Syncthing binary under Termux (same protocol, plainer UI), or
  LocalSend for one-off manual transfers.

### Settings that matter (both sides)

- Folder type: **Send & Receive** on both devices.
- **Staggered file versioning ON (laptop side)** — protects
  against accidental overwrites/deletes of sources.
- `.stignore` in the Library root:
  ```
  (?d)*.tmp-*
  (?d)daily_life.db
  (?d)daily_life.db-wal
  (?d)daily_life.db-shm
  ```
  (`*.tmp-*` because every app write is temp-then-rename — a sync
  tool must never carry a half-written file. The database lines
  are belt-and-braces: the database should never be in this
  folder at all.)
- **Global discovery and relays OFF**; give the laptop a
  DHCP-reserved LAN address (local discovery is unreliable from
  Android — §R7.1).
- Phone run conditions: **Wi-Fi only**, battery exemption granted
  to Syncthing-Fork.
- Conflict copies (`*.sync-conflict-*` files) are rare for the
  near-immutable Library files and safe: check inside before
  deleting one. Sync *packages* that arrive as conflict copies
  are still safe to import — import is idempotent.

## 3. Day-to-day: Sync now

On either device: **Settings → Sync → Sync now** — it writes your
new changes as a package into `Library/sync/` and imports any
packages waiting there from the other device. The screen shows
last export/import per device, a **Conflicts** list (a version
that lost a merge is *preserved there*, never silently dropped),
and a **Held** list (changes dated implausibly far in the future
from a wrong clock — fix that device's clock, export again,
re-import).

## 4. Repair / first pairing (snapshot restore)

Settings → Sync → **Repair from a snapshot…**, or Settings →
Backup → Import — the same machinery (D-011):

1. An automatic pre-restore backup of the current device is
   **always** taken first (it lands in `Library/backups/`).
2. Restoring over a non-empty database requires the explicit
   **"Replace everything"** confirmation. Into an empty database
   it's the fast path.
3. After a repair, run **Sync now** once on both devices. The
   restored device automatically gets a **fresh sync identity**
   (it must not impersonate the device the snapshot came from)
   and re-publishes the restored state as a full package; row
   identities survive, so the other device converges without
   duplicates. One honest limit: deletions made on the other
   device *after* the snapshot was taken are not in it — those
   rows reappear on the repaired device. Treat the repaired
   state as the truth and let packages take over from there.

## 5. Laptop build

```bash
sudo pacman -S --needed gtk3 ninja cmake pkgconf clang sqlite
toolchain/build_linux_on_laptop.sh
```

Desktop differences (§R8.6/R8.7), by design:

- **No share-intent capture** — Android only; on the laptop use
  file import / paste-a-link instead.
- **Reminders don't schedule on desktop** (the platform
  notification service has no Linux scheduling in this build) —
  the phone is the reminder device.
- **HTML quizzes open in the system browser** (no stable Linux
  WebView) via a `file:` URL.
- PDFs, plans, reviews, Learn — everything else is the same app
  on the same data format.

## 6. Stage B (S8) preparation checklist — Avahi

Stage B replaces the manual package carrying with built-in LAN
discovery (`bonsoir`/mDNS). On Linux, mDNS **silently does
nothing unless the Avahi daemon is running** — discovery would
fail and look like a router problem (red-team #9). Before S8
device testing:

```bash
sudo pacman -S --needed avahi nss-mdns
systemctl enable --now avahi-daemon.service
avahi-browse -a   # sanity check: services on the LAN appear
```

Keep the manual fallbacks regardless: Stage B keeps direct-IP
and package sync working with mDNS disabled (that's an S8
acceptance test).
