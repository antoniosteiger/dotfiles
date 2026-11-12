# VPS: Nextcloud, Vaultwarden, Paperless-ngx

Host `vps` (`hosts/vps`, modules in `modules/vps/`). Headless, minimal, hardened.
Backups go to Arcticbox (primary) and Cloudflare R2 (secondary). Secrets via sops-nix.

- [Architecture](#architecture)
- [Decisions and why](#decisions-and-why)
- [Before you start](#before-you-start-placeholders-dns-accounts)
- [First deploy](#first-deploy)
- [Secrets (sops-nix, age)](#secrets-sops-nix-age)
- [Cloudflare and DNS](#cloudflare-and-dns)
- [Exposure toggles](#exposure-toggles)
- [Per-service notes](#per-service-notes)
- [Updates and rollback](#updates-and-rollback)
- [Monitoring](#monitoring-gatus)
- [Backups](#backups)
- [Restore](#restore)
- [Restore test checklist](#restore-test-checklist)

## Architecture

```
internet ──80/443──▶ nginx ──▶ PHP-FPM ─▶ Nextcloud ─┐
tailnet  ──────────▶ nginx ──▶ Vaultwarden           ├─▶ PostgreSQL / Redis (unix sockets)
                           ──▶ Paperless (granian)  ─┘
                           ──▶ Gatus (Tailscale only)
```

| Data | Where | Why |
| --- | --- | --- |
| OS, `/nix`, PostgreSQL, Redis, PHP opcache/tmp | NVMe (root) | latency, small random IO |
| Nextcloud code + apps (`/var/lib/nextcloud`), `tmp/` (tempdirectory, PHP upload tmp) | NVMe | |
| Paperless data dir (index, classifier) `/var/lib/paperless`, scratch `/var/cache/paperless` | NVMe | OCR is many small writes |
| Vaultwarden `/var/lib/vaultwarden`, DB dumps `/var/backup` | NVMe | tiny |
| Nextcloud `datadir` (`/mnt/hdd/nextcloud`: `data/` and `config/`) | HDD | bulk files |
| Paperless media + consume (`/mnt/hdd/paperless/...`) | HDD | bulk files |

The HDD is mounted `noatime`. Everything that writes to it has `RequiresMountsFor`, so
nothing starts (or writes into the bare mount point on the NVMe) while it is missing.
Known exceptions on the HDD: `config.php` (a few KB, opcache keeps it hot), and
Nextcloud's chunked-upload parts, which Nextcloud always writes into the user's own
`uploads/` folder (10 MB sequential chunks, not configurable).

### The HDD is not a disk you control

HostBRR presents the RAID 6 as one virtual `/dev/vdb`. Consequences, all accounted for:

- ZFS raidz2 / mdadm are not possible. The filesystem is plain ext4 (formatting
  advice in `hosts/vps/hardware-configuration.nix`: `-m 0 -i 65536`, not the provider default).
- No snapshots, so no snapshot-consistent backup (see [Backups](#backups)).
- No checksums: silent corruption on the HDD is not detected by the filesystem. restic's
  content hashes and the periodic `restic check --read-data-subset` on Arcticbox are the
  detector.
- RAID health is invisible from inside the VM. Gatus can only check "mounted, rw,
  writable, space, inodes". Ask the provider how they report a degraded array.

### Previews on the NVMe? (evaluated)

Nextcloud keeps thumbnails in `data/appdata_<id>/preview`: thousands of tiny files,
written on demand, read randomly. On a network-attached HDD that makes gallery browsing
slow. **Worth it if you have photo libraries**; irrelevant for documents. It is a pure
cache, so it also gets excluded from backups. It needs the instance id, which exists only
after the first install, hence an option instead of a default:
`vps.nextcloud.previewsToNvme.instanceId = "<id>"` (bind mount from
`/var/lib/nextcloud-previews`). Get the id with
`sudo nextcloud-occ config:system:get instanceid`. The rest of `appdata` (theming,
avatars, app data) stays on the HDD, it is small.

## Decisions and why

- **nginx, not Caddy.** `services.nextcloud` ships a complete nginx vhost (PHP-FPM socket,
  `.well-known`, headers, upload buffering) and nginx integrates with `security.acme`
  (`enableACME`, reload on renewal). Caddy would be a second ACME client plus hand-written
  PHP-FPM config. No concrete advantage here, so nginx.
- **Unix sockets + peer auth for PostgreSQL/Redis.** No DB passwords exist, so there are
  none to leak. (The brief listed "DB passwords" as secrets; this removes them.)
- **Nextcloud pinned to 34** (`pkgs.nextcloud34`). nixpkgs 26.05 has 32 (EOL), 33, 34, 35;
  the module default would be 33. A fresh install starts on 34 to get the longest runway
  without being on the newest. **Majors are bumped one at a time**: 34 → 35, wait until
  `journalctl -u nextcloud-setup` reports success and the admin page is clean, only then
  consider 36. Never skip a major.
- **PostgreSQL pinned to 17**: a major upgrade is a manual dump/restore, never a side effect.
- **Consistency without snapshots: DB first, files second** (see Backups).
- **Gatus checks PostgreSQL/Redis by socket, not TCP.** Both listen on unix sockets only
  (deliberately); a 5-minute `vps-health` unit runs `pg_isready` and `redis-cli ping` and
  pushes the result to Gatus external endpoints.

## Before you start: placeholders, DNS, accounts

Search for what to replace: `grep -rn "TODO\|example.com\|CHANGE_ME" hosts/vps modules secrets .sops.yaml`.

| Where | What |
| --- | --- |
| `hosts/vps/configuration.nix` | `vps.domains.*`, `vps.acme.email`, `vps.ssh.authorizedKeys`, hostname |
| `hosts/vps/hardware-configuration.nix` | boot loader device, root + HDD filesystems (label/UUID) |
| `modules/vps/backup.nix` options | `vps.backup.r2.accountId`, `.bucket`, `vps.backup.arcticbox.host` |
| `modules/vps/updates.nix` options | `vps.autoUpgrade.flake` (public repo, or a `git+ssh` URL + deploy key) |
| `.sops.yaml` | the three age recipients |

Accounts: a domain on Cloudflare, a Tailscale tailnet (VPS and Arcticbox joined), a
Cloudflare R2 bucket + API token.

## First deploy

Order: prepare secrets and placeholders on your PC first (sections below), push to GitHub,
then install. Installing before the secrets exist leaves the services failing on
undecryptable placeholders (loudly; nothing wrong is deployed).

1. **Boot the NixOS installer** on the VPS (provider panel: mount an ISO and use its
   VNC/serial console; or any rescue/Debian image plus nixos-anywhere, which needs a disko
   definition for the NVMe that is not included). Give the installer's `nixos` user a password
   (`passwd`) and enable SSH so you can work from your PC (`sudo systemctl start sshd`).
2. **Partition the NVMe** (`lsblk` first; names may be `vda`/`nvme0n1`). BIOS example
   (`ls /sys/firmware/efi` absent): `parted /dev/vda -- mklabel msdos mkpart primary 1MB 100% set 1 boot on`,
   `mkfs.ext4 -L nixos /dev/vda1`, `mount /dev/disk/by-label/nixos /mnt`. For UEFI add a
   FAT32 ESP and use systemd-boot instead of GRUB in `hardware-configuration.nix`.
3. **Format the HDD once** (needs no mounting in the installer):
   ```
   parted /dev/vdb -- mklabel gpt mkpart primary 0% 100%
   mkfs.ext4 -m 0 -i 65536 -L bulk /dev/vdb1     # slow on 8 TB, be patient
   mkdir -p /mnt/mnt/hdd && chattr +i /mnt/mnt/hdd  # the NEW system's mount point: writes fail while unmounted
   ```
   Do not use the provider's guide verbatim: its `mkfs.ext4` defaults reserve 5 % (400 GB).
4. **Hardware config.** `nixos-generate-config --root /mnt --no-filesystems`, `scp` the
   generated `hardware-configuration.nix` to your PC and merge it into
   `hosts/vps/hardware-configuration.nix` (keep the `fileSystems` blocks, set the real
   labels, set `boot.loader.grub.device`). Commit and push to GitHub (the VPS and
   autoUpgrade pull from there).
5. **Install the host key**, then the system:
   ```
   install -d -m 755 /mnt/etc/ssh
   # from your PC: scp vps_host_key  nixos@<vps>:/tmp/ ; scp vps_host_key.pub nixos@<vps>:/tmp/
   sudo install -m 600 /tmp/vps_host_key /mnt/etc/ssh/ssh_host_ed25519_key
   sudo install -m 644 /tmp/vps_host_key.pub /mnt/etc/ssh/ssh_host_ed25519_key.pub
   sudo nixos-install --flake github:antoniosteiger/dotfiles#vps --no-root-passwd
   ```
   Delete `/tmp/vps_host_key` afterwards and reboot. Keep the provider console open for the
   first boot: if the provider needs static IP config instead of DHCP you will not get SSH.
6. Log in as `toni` (key only). Join Tailscale once: `sudo tailscale up`, approve the node,
   note its `100.x` address for the DNS records of Tailscale-only names.
7. Check: `systemctl --failed`, `journalctl -u nextcloud-setup -u 'acme-*'`, the Gatus page.

Later deploys from your PC: see [Updates and rollback](#updates-and-rollback).

## Secrets (sops-nix, age)

Files: `secrets/vps.yaml` and `secrets/arcticbox.yaml` (sops-encrypted, committed).
`secrets/*.example.yaml` are plaintext templates listing every key. Until the real file
exists **and is `git add`ed** (flakes only see tracked files) builds use the example and
warn; activation then fails to decrypt, it never silently deploys placeholders.

1. Your admin key (offline copy + password manager, **never only on one machine**):
   `age-keygen -o ~/.config/sops/age/keys.txt`.
2. The VPS key is derived from its SSH host key. On a bare VPS that key does not exist
   yet, so **generate it on your PC and install it with the system** (this avoids installing
   twice):
   ```
   ssh-keygen -t ed25519 -N "" -C vps-host -f ./vps_host_key     # outside the repo!
   nix run nixpkgs#ssh-to-age -- -i ./vps_host_key.pub          # prints age1...  -> .sops.yaml (&vps)
   ```
   The private file `vps_host_key` is copied to `/mnt/etc/ssh/ssh_host_ed25519_key` during
   install (see First deploy) and also stored in your password manager: it is the VPS's
   age key. Arcticbox: `nix run nixpkgs#ssh-to-age -- -i /etc/ssh/ssh_host_ed25519_key.pub` on it.
3. Put the three public keys in `.sops.yaml`.
4. `cp secrets/vps.example.yaml secrets/vps.yaml`, fill it, `sops --encrypt --in-place secrets/vps.yaml`
   (or just `sops secrets/vps.yaml`). `git add secrets/vps.yaml`.

Generating values: `openssl rand -base64 48` for passwords/tokens/Paperless secret key;
Vaultwarden: `nix run nixpkgs#vaultwarden -- hash` (store the hash; the plaintext is your
`/admin` password); htpasswd: `nix run nixpkgs#apacheHttpd -- ...` or
`nix shell nixpkgs#apacheHttpd -c htpasswd -nbB vps '<pw>'`.

| Secret | Used by |
| --- | --- |
| `nextcloud/admin_password` | first install of the `admin` user |
| `vaultwarden/admin_token` (argon2 hash) | `/admin` |
| `paperless/admin_password`, `paperless/secret_key` | superuser `admin`, Django secret |
| `cloudflare/dns_api_token` | ACME DNS-01 (Zone:Zone:Read + Zone:DNS:Edit, one zone) |
| `restic/arcticbox_password` | repo password, Arcticbox repo |
| `restic/arcticbox_rest_password` | REST user `vps` (hash in `arcticbox.yaml`) |
| `restic/r2_password`, `r2/access_key_id`, `r2/secret_access_key` | R2 repo |
| `gatus/token_*` (5) | each push endpoint's bearer token |
| `smtp/password` | optional, `vps.monitoring.email.enable` |

> **Back up the age key outside the VPS.** The VPS's age key *is* its SSH host key; if the
> VPS dies, secrets are only recoverable with your admin key. Also keep the two restic
> repo passwords in your password manager: without them the backups are unreadable. A
> restic repo password cannot be recovered.

## Cloudflare and DNS

- Token: Zone:Zone:Read + Zone:DNS:Edit, restricted to the one zone.
- **Nextcloud (and in general all records) must be DNS-only (grey cloud), not proxied:**
  Cloudflare's proxy caps request bodies at 100 MB (free plan), which breaks large uploads.
- Public names: `A`/`AAAA` to the VPS's public IP.
- Tailscale-only names (Gatus always, `/admin` hostnames if you move to tailscale
  exposure): `A` to the VPS's **Tailscale IP** (`100.x.y.z`). DNS-01 gives them real
  certificates without being reachable from the internet.

## Exposure toggles

Set in `hosts/vps/configuration.nix`; one line each.

| Option | Default | Notes |
| --- | --- | --- |
| `vps.nextcloud.exposure` | `public` | `tailscale`: no public share links, clients need Tailscale; DNS record must point at the Tailscale IP |
| `vps.vaultwarden.exposure` | `public` | `/admin` is Tailscale-only in both cases |
| `vps.paperless.exposure` | `public` | hardened when public (below); `tailscale` removes the exposure |
| Gatus | Tailscale only | not configurable |

"Tailscale-only" is enforced by an nginx ACL (`100.64.0.0/10`, `fd7a:115c:a1e0::/48`,
loopback; everything else gets 403). Ports 80/443 stay open for the other vhosts. The
status page stays unreachable from the internet regardless of DNS.

## Per-service notes

### Nextcloud
- First admin: user `admin`, password from sops. Create your normal user, then stop using admin.
- Apps are declarative (`extraApps`: calendar, contacts, notes, tasks); the app store is off.
- Background jobs: systemd timer `nextcloud-cron.timer` (5 min).
- CLI: `sudo nextcloud-occ ...`.
- Tuned for 8 GB: PHP-FPM `pm.max_children = 12`, PostgreSQL `shared_buffers = 512MB`,
  Redis `maxmemory 256mb`, zram swap. Raise them if you move to a bigger VPS.

### Vaultwarden
- `SIGNUPS_ALLOWED = false`. First account: set it to `true` in `modules/vps/vaultwarden.nix`,
  deploy, register, set back to `false`, deploy.
- `/admin` from the tailnet only, log in with the plaintext of the hash in sops.
- fail2ban jail on failed logins (public mode).

### Paperless-ngx
- **2FA (TOTP):** user menu (top right) → *My Profile* → *Two-factor authentication* →
  enable TOTP, scan, save the recovery codes. There is no switch to force it; do it for
  every user.
- Public hardening: nginx `limit_req` (6/min, burst 5) on `/accounts/login/` and
  `/api/token/`, fail2ban jail `paperless` (5 failures / 10 min → 1 h ban, reads
  `/var/log/nginx/paperless.access.log`), security headers.
- `paperless-manage` needs root (`sudo paperless-manage ...`).
- **Optional one-way ingest from Nextcloud** (`vps.paperless.consumeFromNextcloud.enable`):
  Paperless consumes (and deletes) files in `<ncdatadir>/data/<user>/files/<folder>`;
  a 10-minute `occ files:scan --path` refreshes Nextcloud's cache. Enable it only after
  that user has logged in once and the folder exists. Paperless storage is never
  exposed to Nextcloud.
- **Optional monthly export** (`vps.paperless.exporter.enable`): `document_exporter` into
  `/mnt/hdd/paperless/export` (included in the backups). Paperless is stopped while it runs.

## Updates and rollback

**Automatic:** `system.autoUpgrade` at 03:30 (+ up to 30 min), from
`vps.autoUpgrade.flake`, with nixpkgs re-resolved to the tip of `nixos-26.05`
(`vps.autoUpgrade.followChannel = false` makes it use only the committed `flake.lock`).
It reboots only when the kernel/initrd changed and only between 03:00 and 05:00;
otherwise the new generation is staged. Nextcloud and PostgreSQL majors never move on
their own (pinned). The run pushes success/failure to Gatus.

**Manual** (from your PC, in the repo):
```
nix flake update                      # or: nix flake update nixpkgs
nixos-rebuild switch --flake .#vps --target-host toni@<vps> --sudo
```
`--sudo` is `--use-remote-sudo` on older nixos-rebuild. Root login is disabled; `toni`
has passwordless sudo (key-only login).

**Rollback:** `sudo nixos-rebuild switch --rollback` on the VPS, or pick an older
generation in the boot menu / provider console. Generations are kept until the weekly
`nix.gc` (older than 14 days). A Nextcloud *major* bump cannot be rolled back by
generation: restore the DB dump taken before it.

## Monitoring (Gatus)

`https://<vps.domains.status>` (tailnet only). No notifications by default.

- HTTP: Nextcloud `/status.php`, Vaultwarden `/alive`, Paperless `/accounts/login/`:
  status 200, response time, certificate expiry > 14 days.
- Pushed (Gatus *external endpoints*, token per endpoint in sops): `restic-arcticbox-data`,
  `restic-arcticbox-state`, `restic-r2`, `nixos-autoupgrade` (36 h window each,
  `vps.monitoring.heartbeat.*`), and every 5 min `disk-nvme`, `disk-hdd` (space + inodes,
  `vps.monitoring.diskUsageLimitPercent`), `hdd-mount` (mounted, rw, writable),
  `postgresql`, `redis` (30 min window).
- A backup run skipped because Arcticbox is off pushes nothing; the 36 h window is what
  turns "off for too long" red. Real failures push `failure` immediately.
- **Email alerts (off):** `vps.monitoring.email.enable = true` plus host/port/username/from/to
  and `smtp/password` in sops. Infomaniak: host `mail.infomaniak.com`, port 587 (STARTTLS),
  username and from = the full mailbox address (verify against Infomaniak's SMTP docs; use a
  mailbox/device password if you have 2FA). Test: `sudo gatus-push disk-nvme failure test` three times
  (failure-threshold is 3), then once `success` to see the resolved mail. Cloudflare Email
  Routing is inbound-only and Email Sending needs the Workers paid plan, so nothing here
  assumes either.
- Not covered: RAID health (provider side), and **failures of the prune/check job on
  Arcticbox**, which show only in its journal (`journalctl -u 'restic-prune-*'`).

## Backups

RAID is not backup, sync is not backup. Two independent restic repositories:

| | Primary | Secondary |
| --- | --- | --- |
| Target | restic REST server on Arcticbox, **append-only**, Tailscale only | Cloudflare R2 (S3) |
| Jobs | `arcticbox-state` hourly `:05`, `arcticbox-data` hourly `:35` | `r2` daily 03:30 |
| Content | state: DB dumps, Vaultwarden, `config/`, Paperless media (+export dir); data: Nextcloud `data/` (previews excluded) | state set only (no Nextcloud files) |
| Retention | on Arcticbox: 7 daily / 4 weekly / 12 monthly (`services.resticBackupServer.retention`) + `restic check --read-data-subset=5%` weekly | on the VPS: 7 daily / 4 weekly / 3 monthly, `check` 2 % daily |
| Why | the VPS cannot delete or alter history; ransomware/compromise on the VPS cannot destroy it | covers Arcticbox being off, second location |

**Consistency approach.** There are no snapshots (provider-virtualised ext4), and
Nextcloud in maintenance mode hourly, or for the days the first run takes, is not an
option. So `vps-db-dump` runs first, as a hard dependency of every job: `pg_dump` of the
Nextcloud and Paperless databases and the Vaultwarden module's `sqlite3 .backup`
(never a raw copy of a live SQLite file). Only then are files read. The only possible
skew is "file newer than the DB dump", which `occ files:scan --all` repairs at restore
time. Dumps are plain SQL on purpose so restic dedups them.

**Interrupted / resumable.** Hourly timers; a run that is cut off (reboot, Arcticbox
sleeping, SIGTERM) just ends, and the next tick starts again. Finished packs are never
re-uploaded (dedup), no unit has `Restart=` so nothing loops. Every run starts with
`restic unlock`, which removes only *stale* locks (allowed on an append-only server), and
passes `--retry-lock=30m`. Before anything else an `ExecCondition` checks that Arcticbox
answers HTTP; if not the run is **skipped quietly** (not a failure, nothing pushed).
Jobs run at idle IO priority and `Nice=15`.

**First run:** ~8 TB over Tailscale takes days. Interrupt freely (stop the unit, reboot,
shut Arcticbox down). Note restic only creates a snapshot when a run finishes, so an
interrupted first run re-reads files it already uploaded (hashing again, no re-upload).

### Arcticbox setup

Shipped **disabled** so your next `nixos-rebuild switch` on Arcticbox changes nothing.
To enable:
1. Mount the storage disk at `/srv/restic` (add a `fileSystems."/srv/restic"` entry).
   Until it is a real mount point the REST server, its socket and the prune job do not
   start (`ConditionPathIsMountPoint`), so the root disk cannot be filled by accident.
2. Create `secrets/arcticbox.yaml` (see `.sops.yaml`): `restic/vps_password` (equal to
   `restic/arcticbox_password` in the VPS file) and `restic/server_htpasswd`
   (`htpasswd -nbB vps '<arcticbox_rest_password>'`).
3. In `hosts/arcticbox/configuration.nix` set `services.resticBackupServer.enable = true`
   and rebuild. Tailscale is enabled by the module; join once with `sudo tailscale up`.
   Port 8000 opens on `tailscale0` only.

### R2 setup
Bucket `vps-backup`, an API token with object read/write on that bucket only, account id
into `vps.backup.r2.accountId`. The VPS holds credentials that can delete, so R2 is not
tamper-proof; consider a bucket lock/retention rule in Cloudflare.

### Gaps where only one copy exists
- **Nextcloud files exist on the VPS HDD and on Arcticbox only.** R2 deliberately has no
  files. If Arcticbox is off for a long time and the HDD is lost, they are gone; and
  Arcticbox is probably in the same place as you (no offsite copy of the files).
- Anything changed since the last successful run (up to ~36 h if Arcticbox is off) exists
  only on the VPS. DB dumps and Vaultwarden are protected by R2 within a day.
- The VPS host SSH key = its age key, your admin age key, and both restic repo passwords:
  single copies unless you store them elsewhere.
- Paperless data dir (index, classifier) is **not** backed up on purpose: it is rebuilt by
  `paperless-manage document_index reindex` and retraining.
- The R2 repo can be deleted by a compromised VPS (see above).
- (Not applicable here, since the disk is not yours: ZFS `zfs send`/syncoid pulled from
  Arcticbox would have been an alternative with true snapshots and block-level
  efficiency; it requires controlling the disks.)

## Restore

Set up access first. On Arcticbox, work on the repository directly:
`export RESTIC_REPOSITORY=/srv/restic/vps RESTIC_PASSWORD_FILE=...`. From elsewhere over
Tailscale: `export RESTIC_REPOSITORY=rest:http://vps:<pw>@tonix-desktop:8000/vps/`.
R2: `export RESTIC_REPOSITORY=s3:https://<account>.r2.cloudflarestorage.com/<bucket> AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_DEFAULT_REGION=auto`
and the `restic/r2_password`. Then `restic snapshots`.

**Whole machine lost.**
1. Reinstall the VPS from this flake (same SSH host key if you saved it, else generate a
   new one, derive its age key and `sops updatekeys secrets/vps.yaml`). The first boot
   creates empty databases and an empty Nextcloud; that is fine.
2. Stop the services: `systemctl stop phpfpm-nextcloud nextcloud-cron.timer 'paperless-*' vaultwarden`.
3. Restore files (target `/`, paths are absolute):
   `restic restore latest --tag nextcloud-data --target /` and
   `restic restore latest --tag state --target /`. This puts back `${datadir}/data`,
   `${datadir}/config/config.php` (it holds instanceid, secret and passwordsalt: it must
   match the DB), Paperless media, `/var/backup` (dumps, Vaultwarden copy).
4. Databases (the dump has `--clean --if-exists`, restore as the postgres superuser):
   ```
   sudo -u postgres psql -d nextcloud -f /var/backup/db/nextcloud.sql
   sudo -u postgres psql -d paperless -f /var/backup/db/paperless.sql
   ```
5. Vaultwarden: `systemctl stop vaultwarden`, copy `/var/backup/vaultwarden/*` into
   `/var/lib/vaultwarden/`, `chown -R vaultwarden:vaultwarden /var/lib/vaultwarden`.
6. Ownership: `chown -R nextcloud:nextcloud /mnt/hdd/nextcloud`,
   `chown -R paperless:paperless /mnt/hdd/paperless`.
7. Start everything, then **`sudo nextcloud-occ files:scan --all`** (picks up files newer
   than the DB dump) and `sudo nextcloud-occ maintenance:repair`. Paperless:
   `sudo paperless-manage document_index reindex`.

**Only a database / only R2 available** (Arcticbox gone): restore the `state` snapshot
from R2: DBs, Vaultwarden and Paperless media are complete; Nextcloud *files* are lost
if the HDD is also lost, but the metadata and config.php survive.

**One file / folder:** `restic mount /mnt/restore` (or `restic restore latest --include <path> --target /tmp/r`).

**Paperless without a matching version:** if you enabled the exporter, use
`document_importer` on the export in `/mnt/hdd/paperless/export`.

## Restore test checklist

Do this after the first full backup, then every few months and after major changes.

- [ ] `restic snapshots` on both repos shows recent `state`, `nextcloud-data` (Arcticbox) and `state` (R2) snapshots.
- [ ] Gatus: all `backups` endpoints green; no `health` failures.
- [ ] On Arcticbox the weekly prune/check ran (`journalctl -u 'restic-prune-vps'`) and `restic check` passed.
- [ ] Restore the `state` snapshot into a scratch directory; open the SQL dumps (`head`), compare sizes with the live DBs.
- [ ] `restic restore` one Nextcloud file, compare its checksum with the live file.
- [ ] Load the Nextcloud dump into a throwaway PostgreSQL (`createdb`, `psql -f`) without errors.
- [ ] Open the Vaultwarden `db.sqlite3` copy with `sqlite3 ... 'pragma integrity_check; select count(*) from users;'`.
- [ ] Restore from R2 as well (different password, different credentials).
- [ ] Restore the repo password and age key from your offline copy (prove they work).
- [ ] Optional full drill: a spare VM, whole-machine procedure above.

## Assumptions and open questions

Assumptions made (change any of them in the module options):

- "/src/restic" was read as `/srv/restic`.
- The VPS has BIOS boot, virtio disks (`/dev/vda` NVMe-class root, `/dev/vdb` HDD); both are placeholders.
- Your tailnet resolves the short name `tonix-desktop` (MagicDNS) from the VPS.
- The dotfiles repo `github:antoniosteiger/dotfiles` is reachable by the VPS without credentials for autoUpgrade.
- `toni` is the only SSH user, root login is off, and `toni` has passwordless sudo (key-only).
- Nextcloud 34, PostgreSQL 17, languages `deu+eng` for OCR, region `DE`, timezone from `base.nix`.
- R2 gets the Paperless media (you said < 20 GB); it never gets Nextcloud files.
- Arcticbox ships with the backup server disabled; the VPS backups simply skip while it is unreachable.
- Email alerts, the Paperless exporter, ingest-from-Nextcloud and the NVMe preview cache are all off by default.

Decided (since the first draft): no additional offsite copy of the Nextcloud files (cost); the
dotfiles repo is public (no deploy key needed); the provider gives no RAID information; Arcticbox is
not reported to Gatus; alerts use Infomaniak SMTP (see Monitoring).

Still open:

- The HDD cannot be snapshotted by you: ask HostBRR whether LVM/snapshots or a different volume type exist.
