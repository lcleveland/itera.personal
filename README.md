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
(`impermanence`) — **installing wipes the target disk.** Verify
`itera.disko.device` in [hosts/dream.nix](hosts/dream.nix) /
[hosts/framework.nix](hosts/framework.nix) with `lsblk` before installing.

## User & password

The single user `lcleveland` is declared in [hosts/common.nix](hosts/common.nix)
with a temporary `initialPassword` (= `lcleveland`). **Change it after first login
with `passwd`.** A secrets-managed password (e.g. agenix +
`users.users.lcleveland.hashedPasswordFile`) can be added later.

## Installing from the live ISO

Boot the official [NixOS ISO](https://nixos.org/download) (minimal or graphical).
disko partitions/formats/mounts and `nixos-install` runs in one step via
`disko-install`, matching itera's own installer. Replace `dream` with `framework`
for the laptop.

1. **Network + tools.** Get online (`nmcli` on the graphical ISO, or Ethernet). A
   recent ISO already ships `nix` with flakes usable via the flags below.

2. **Get this config.** Clone it somewhere writable on the live system:

   ```sh
   nix-shell -p git --run 'git clone https://github.com/lcleveland/itera.personal /tmp/cfg'
   cd /tmp/cfg
   ```

3. **Pick the disk.** `lsblk` to find the target, then set `itera.disko.device`
   in [hosts/dream.nix](hosts/dream.nix) to match (e.g. `/dev/nvme0n1`, `/dev/sda`).
   **Everything on that disk is erased.**

4. **Partition + install** (disko wipes the disk, formats it, mounts under `/mnt`,
   and installs — all in one command; disk key is `main`):

   ```sh
   sudo env NIX_CONFIG="extra-experimental-features = nix-command flakes
   accept-flake-config = true" \
     nix run 'github:nix-community/disko/latest#disko-install' -- \
     --flake '/tmp/cfg#dream' --disk main /dev/nvme0n1
   ```

   <details><summary>Two-step alternative (if you prefer explicit disko + nixos-install)</summary>

   ```sh
   # format & mount to /mnt from the config's disko layout
   sudo nix --extra-experimental-features 'nix-command flakes' \
     run 'github:nix-community/disko/latest' -- \
     --mode destroy,format,mount --flake '/tmp/cfg#dream'
   # install
   sudo nixos-install --flake '/tmp/cfg#dream'
   ```
   </details>

5. **Reboot** and remove the ISO. Log in as `lcleveland` / `lcleveland`, then
   **change the password** with `passwd`.

6. **Get a persisted checkout** for future rebuilds. Clone this repo into
   `~/Documents/itera.personal` (the path `itera.nix.nh.flake` and impermanence
   expect):

   ```sh
   git clone https://github.com/lcleveland/itera.personal ~/Documents/itera.personal
   ```

## Rebuild

`itera.nix.nh.flake` points at this checkout, so after install:

```sh
sudo nh os switch
```

## Notes

- Eiros hardware workarounds (dream MT7927 initrd timeout, Framework MT7922
  Bluetooth quirks) were intentionally **not** carried over.
