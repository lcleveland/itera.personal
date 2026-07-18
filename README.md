# itera.personal

lcleveland's NixOS configuration, built on [itera](https://github.com/lcleveland/itera)
(a batteries-included, opt-out layer using hjem, disko, impermanence, and the
mango/DankMaterialShell desktop).

## Hosts

| Flake attr  | Hostname   | Machine                    | Notes                                              |
|-------------|------------|----------------------------|----------------------------------------------------|
| `dream`     | `DREAM`    | AMD desktop                | dual monitor, gaming (Steam), local AI (ollama)    |
| `framework` | `LS-04380` | Framework 16 (7040 AMD)    | fingerprint, printing, Colemak-DH, three monitors  |

Both use itera's declarative disk layout (`disko`) with a tmpfs root
(`impermanence`) — **installing wipes the target disk.** The target disk is
chosen at install time with `disko-install --disk main /dev/<disk>`; the
`itera.disko.device` value in the host files is a fail-safe placeholder that the
install command overrides, so you never edit the repo to install.

## User & password

The single user `lcleveland` is declared in [hosts/common.nix](hosts/common.nix)
with a temporary `initialPassword` (= `lcleveland`). **Change it after first login
with `passwd`.** A secrets-managed password (e.g. agenix +
`users.users.lcleveland.hashedPasswordFile`) can be added later.

## Installing from the live ISO

Boot the official [NixOS ISO](https://nixos.org/download) (minimal or graphical),
get online (`nmcli` on the graphical ISO, or plug in Ethernet), then run the
installer straight from GitHub — **nothing to clone or edit:**

```sh
curl -sSL https://raw.githubusercontent.com/lcleveland/itera.personal/main/install.sh | sudo bash
```

[install.sh](install.sh) prompts you to **pick the host** (`dream` / `framework`)
and the **disk**, confirms the destructive wipe, then hands off to `disko-install`
(partition + format + mount + `nixos-install`, in one step). Skip either prompt by
passing them as arguments:

```sh
curl -sSL .../install.sh | sudo bash -s -- dream               # host given, pick disk
curl -sSL .../install.sh | sudo bash -s -- dream /dev/nvme0n1  # fully non-interactive
```

<details><summary>Manual equivalent (no script)</summary>

`--disk main /dev/<disk>` overrides the placeholder device in the config, so the
repo needs no editing:

```sh
sudo env NIX_CONFIG="extra-experimental-features = nix-command flakes
accept-flake-config = true" \
  nix run 'github:nix-community/disko/latest#disko-install' -- \
  --flake 'github:lcleveland/itera.personal#dream' \
  --disk main /dev/nvme0n1
```
</details>

After it finishes:

1. **Reboot** and remove the ISO. Log in as `lcleveland` / `lcleveland`, then
   **change the password** with `passwd`.

2. **(Optional) Get a checkout** if you want to edit the config locally. Rebuilds
   don't need it — `itera.update.flake` points at the GitHub remote — but a clone
   is handy for making changes before pushing:

   ```sh
   git clone https://github.com/lcleveland/itera.personal ~/Documents/itera.personal
   ```

## Rebuild

Both hosts configure itera's update battery ([hosts/common.nix](hosts/common.nix)
sets `itera.update.flake` to `github:lcleveland/itera.personal`, and each host sets
`itera.update.configuration` to its flake attr — `dream` / `framework` — since the
hostnames `DREAM` / `LS-04380` don't match). So the `itera` command needs no
arguments and no checkout on disk:

```sh
itera rebuild   # nh os switch from the configured remote flake + host
itera update    # --refresh to the newest pushed revision, then rebuild
itera boot      # rebuild, but apply on next reboot
itera gc        # prune old generations
```

Equivalent one-shot rebuild without the `itera` command:

```sh
sudo nixos-rebuild switch --flake github:lcleveland/itera.personal#dream
```

## Notes

- Eiros hardware workarounds (dream MT7927 initrd timeout, Framework MT7922
  Bluetooth quirks) were intentionally **not** carried over.
