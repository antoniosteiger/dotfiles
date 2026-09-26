# tonix

NixOS configuration for two machines, managed as a single flake.

| Host | Hostname | Machine |
| --- | --- | --- |
| `lenovo_t14s_gen2` | `tonix-laptop` | ThinkPad T14s Gen2 (AMD) |
| `arcticbox` | `tonix-desktop` | Desktop |

## What this setup is

A Wayland desktop built on **NixOS** with **Hyprland** as the compositor and
**Noctalia** as the desktop shell. Noctalia is the important piece: rather than
assembling a bar, a notification daemon, a launcher, a lockscreen, an idle
manager and a wallpaper tool separately, Noctalia provides all of them as one
program, and also generates the colour themes for other applications from a
single palette.

Everything is declared here. The only things not in this repo are secrets
(1Password, the GNOME keyring) and Noctalia's own generated theme files.

### System layers

| Task | Tool |
| --- | --- |
| Operating system | NixOS 26.05 (flake + home-manager as a NixOS module) |
| Bootloader | GRUB (EFI, hidden menu, no splash image) |
| Init / service manager | systemd |
| Login screen (greeter) | `noctalia-greeter` |
| Session launcher | UWSM (`hyprland-uwsm`) |
| Compositor / window manager | Hyprland (Wayland) |
| Desktop shell — bar, notifications, launcher, OSD, lockscreen, idle, wallpaper, screenshots, colour picker panel, power menu | **Noctalia** |
| System theming | Noctalia templates (GTK, Qt, ghostty, btop, starship, neovim, yazi, sioyek, discord, …) |
| Audio | PipeWire + WirePlumber |
| Graphics | Mesa (AMD / radeonsi) |
| Networking | NetworkManager |
| Printing | CUPS |
| Portals | `xdg-desktop-portal-hyprland` + `-gtk` |
| File picker | `xdg-desktop-portal-termfilechooser` → yazi in a floating Ghostty |
| Removable media | udisks2 + udiskie (auto-mount) |
| Secrets / keyring | GNOME Keyring (`login` keyring, unlocked by PAM) |
| Passwords | 1Password |
| Terminal | Ghostty |
| Shell | zsh + starship |
| Editor | Neovim (vim kept for root) |
| File manager | yazi |
| Browser | Firefox (Chrome kept for compatibility/Lighthouse) |
| PDF viewer | sioyek |
| Colour picker | hyprpicker |
| Screenshots | Noctalia (native screencopy — no grim/slurp) |
| Media control | Noctalia (native MPRIS — no playerctl) |
| Fonts | JetBrains Mono Nerd Font, DejaVu |
| Generation cleanup | `nh clean` (see below) |

Noctalia replaced a pile of single-purpose tools that used to live here:
hyprpaper, hyprlock, hypridle, waybar, swaync, wayle, vicinae — and stylix for
theming. If you are tempted to add a small tool, check whether Noctalia already
does it (`noctalia msg --help`).

## Rebuilding

Standard way:

```sh
sudo nixos-rebuild switch --flake ~/dotfiles#lenovo_t14s_gen2   # laptop
sudo nixos-rebuild switch --flake ~/dotfiles#arcticbox          # desktop
```

With `nh` (nicer output, shows a package diff before activating):

```sh
nh os switch -H lenovo_t14s_gen2 --ask    # laptop
nh os switch -H arcticbox --ask           # desktop
```

`nh` handles privilege elevation itself — do **not** prefix it with `sudo`.

Useful variants:

```sh
nh os boot -H lenovo_t14s_gen2     # stage for next boot, don't activate now
nh os test -H lenovo_t14s_gen2     # activate now, don't make it the boot default
nh os rollback                     # back to the previous generation
```

## Gotchas

Hard-won; most of these cost real debugging time.

### The hostname does not match the flake attribute

`nh` and `nixos-rebuild` both default to the **local hostname** when picking a
configuration. The hostnames (`tonix-laptop`, `tonix-desktop`) differ from the
flake attributes (`lenovo_t14s_gen2`, `arcticbox`), so the short forms fail:

```sh
nh os switch            # fails: no nixosConfiguration "tonix-laptop"
nh os switch -H lenovo_t14s_gen2   # works
```

Renaming the flake attributes to match the hostnames would remove the need for
`-H` and `#host` entirely. Not done yet.

### Shared config needs modules added to *both* hosts

`hosts/common/configuration.nix` is imported by both machines. If it uses an
option from a flake input's module (e.g. `services.displayManager.noctalia-greeter`),
that module must be listed in **both** hosts' `modules` lists in `flake.nix`.
Missing it on one host makes that host fail to evaluate — and you will not
notice, because you usually only rebuild the machine you are sitting at.

Check both before committing:

```sh
nix eval .#nixosConfigurations.lenovo_t14s_gen2.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.arcticbox.config.system.build.toplevel.drvPath
```

### The keyring prompt: `default` must point at `login`

If applications keep asking to unlock a keyring, check:

```sh
cat ~/.local/share/keyrings/default    # must say: login
```

PAM (`pam_gnome_keyring.so auto_start`) unlocks the **`login`** keyring with your
login password at session start. If the *default* collection is anything else
(e.g. a `Default_keyring` created by an app), nothing unlocks it and every app
that stores a secret prompts for a password. Point `default` at `login`.

### Never add `xdg-desktop-portal-wlr` alongside Hyprland

`programs.hyprland.enable` already pulls in `xdg-desktop-portal-hyprland`. Adding
the wlr portal too means two implementations of ScreenCast fight, and wlr wins if
it is listed first in `xdg.portal.config.common.default` — which loses the
window/output picker. Correct setting:

```nix
xdg.portal.config.common.default = [ "hyprland" "gtk" ];
```

### Noctalia writes generated files into this repo

`home.nix` symlinks the whole `~/.config/sioyek` directory out of the store to
`config/sioyek`, and Noctalia's theme templates write into it. So
`config/sioyek/themes/noctalia.config` is **generated output committed to git**
and will show up as modified whenever the palette changes. Same idea for
`~/.config/hypr/noctalia.conf`, which is generated but *not* in this repo.

### Hyprland config ordering

`config/hypr/hyprland.conf` sources two generated/host files:

- `~/.config/hypr/host-specific.conf` — in the middle of the file
- `~/.config/hypr/noctalia.conf` — at the very end (colours)

**Later definitions win.** Two consequences that have already bitten:

- Do not set `col.active_border` in `general {}`; Noctalia's file overrides it
  silently at the end.
- Keybinds in `host-specific.conf` are overridden by anything bound later in
  `hyprland.conf` — this is why the `brightnessctl` binds were dead code.

Duplicate binds do not warn. `$mod + Space` was silently bound twice.

### `nix.gc` cannot keep *N* generations

`nix-collect-garbage` only supports `--delete-old` and `--delete-older-than
<period>`. There is no count-based flag, so `nix.gc.options` cannot express
"keep 4". This repo uses `nh` instead:

```nix
nix.gc.automatic = false;          # must not run alongside nh-clean
programs.nh.clean.extraArgs = "--keep 4 --keep-since 7d";
```

`programs.nh.clean.enable` and `nix.gc.automatic` must **not** both be on. The
module only emits a *warning*, not an error, so they will happily both run.

One-off cleanup (the weekly timer does not touch an existing backlog):

```sh
nh clean all --keep 4 --keep-since 7d --dry   # preview
nh clean all --keep 4 --keep-since 7d
sudo nixos-rebuild boot --flake ~/dotfiles#lenovo_t14s_gen2   # refresh GRUB entries
```

Deleting generations leaves stale GRUB entries pointing at deleted store paths,
hence the `boot` afterwards.

### Reboot before garbage-collecting after boot changes

If `/run/booted-system` differs from `/run/current-system`, you have switched but
not rebooted, and the new kernel/bootloader config is untested. Garbage-collect
*after* a successful reboot, so old generations are still there to roll back to.

```sh
readlink /run/booted-system /run/current-system
```

### Surprising size traps

Measured on the laptop; see `tools/weigh.sh`.

| Trap | Cost |
| --- | --- |
| `services.speechd` is **on by default** in NixOS and pulls espeak → mbrola → mbrola-voices | 645 MiB |
| `nixos-hardware`'s `common/gpu/amd` turns on `hardware.graphics.enable32Bit`, duplicating Mesa + LLVM | 884 MiB |
| `ltex-ls-plus` (nvim spell-check) pulls a headless JDK | 822 MiB |
| Two cursor theme packages (greeter vs session) | ~690 MiB |
| Steam's FHS env pulls the full 223 MiB `glibc-locales` regardless of `i18n.supportedLocales` | 223 MiB |

Most "minimise NixOS" advice (`environment.defaultPackages = []`, the `perlless`
profile, `command-not-found`) is written for container images and saves ~3 MiB
each on a desktop. The base OS here is already ~0.9 GiB; the weight is
applications.

### `nh os switch --dry` reports a nonsense size diff

`--dry` does not build, so unrealized paths are not counted and the reported
`SIZE:` / `DIFF:` numbers are wildly wrong. Ignore them; the diff on a real run
is accurate.

## Layout

```
flake.nix                  inputs + both host definitions
home.nix                   home-manager (shared by both hosts)
hosts/common/              shared NixOS config
hosts/<host>/              per-machine config + hardware-configuration.nix
config/hypr/               hyprland.conf + host-laptop.conf / host-desktop.conf
config/noctalia/           desktop shell config
config/{zsh,starship,neovim,sioyek,xdg-desktop-portal-termfilechooser}/
tools/weigh.sh             report closure size, heaviest packages, boot time, idle RAM
```

Files under `config/` are symlinked out of the store with
`mkOutOfStoreSymlink`, so editing them takes effect without a rebuild (a
Hyprland reload or app restart is usually enough).
