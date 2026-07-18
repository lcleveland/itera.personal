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

Boot the official [NixOS ISO](https://nixos.org/download) (minimal or graphical).
The install runs **directly from the flake on GitHub — no cloning or editing
first.** `disko-install` partitions, formats, mounts, and installs in one step.
Replace `dream` with `framework` for the laptop.

1. **Network.** Get online (`nmcli` on the graphical ISO, or plug in Ethernet).

2. **Pick the disk.** `lsblk` to find the target (e.g. `/dev/nvme0n1`, `/dev/sda`).
   **Everything on that disk is erased.**

3. **Partition + install** in one command. `--disk main /dev/<disk>` overrides the
   placeholder device baked into the config, so nothing in the repo needs editing:

   ```sh
   sudo env NIX_CONFIG="extra-experimental-features = nix-command flakes
   accept-flake-config = true" \
     nix run 'github:nix-community/disko/latest#disko-install' -- \
     --flake 'github:lcleveland/itera.personal#dream' \
     --disk main /dev/nvme0n1
   ```

4. **Reboot** and remove the ISO. Log in as `lcleveland` / `lcleveland`, then
   **change the password** with `passwd`.

5. **(Optional) Get a persisted checkout** for convenient rebuilds. Clone the repo
   to `~/Documents/itera.personal` (the path `itera.nix.nh.flake` expects) so
   `sudo nh os switch` works against a local tree:

   ```sh
   git clone https://github.com/lcleveland/itera.personal ~/Documents/itera.personal
   ```

## Rebuild

Straight from the remote flake, no checkout needed:

```sh
sudo nixos-rebuild switch --flake github:lcleveland/itera.personal#dream
```

Or, with a local checkout at `~/Documents/itera.personal` (see install step 5),
`itera.nix.nh.flake` points there so you can just run:

```sh
sudo nh os switch
```

## Notes

- Eiros hardware workarounds (dream MT7927 initrd timeout, Framework MT7922
  Bluetooth quirks) were intentionally **not** carried over.
