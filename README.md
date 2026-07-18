# itera.personal

lcleveland's NixOS configuration, built on [itera](https://github.com/lcleveland/itera)
(a batteries-included, opt-out layer using hjem, disko, impermanence, agenix, and
the mango/DankMaterialShell desktop).

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

The single user `lcleveland` is declared in [hosts/common.nix](hosts/common.nix).
The login password is stored with **agenix** (`secrets/lcleveland-password.age`,
an mkpasswd hash) and wired via `users.users.lcleveland.hashedPasswordFile`. The
secret decrypts at activation with the host's ed25519 SSH key (persisted by
impermanence).

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

4. **Disable the password secret for the first install.** The agenix
   `.age` does not exist yet (the host key is created on first boot), so comment
   out these two lines or the build fails:
   - `itera.secrets.secrets.lcleveland-password.file = ...` in
     [hosts/common.nix](hosts/common.nix)
   - `users.users.lcleveland.hashedPasswordFile = ...` in the same file

   First login then uses the fallback `initialPassword` (= `lcleveland`).

5. **Partition + install** (disko wipes the disk, formats it, mounts under `/mnt`,
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

6. **Reboot** and remove the ISO. Log in as `lcleveland` / `lcleveland`, then
   continue to the agenix bootstrap below to switch to the real password.

## agenix password bootstrap (after first boot)

agenix decrypts with the host's ed25519 key, which only exists after the first
boot — so finish the password wiring on the installed system:

1. **Get a persisted checkout.** Clone this repo into `~/Documents/itera.personal`
   (the path `itera.nix.nh.flake` and impermanence expect):

   ```sh
   git clone https://github.com/lcleveland/itera.personal ~/Documents/itera.personal
   cd ~/Documents/itera.personal
   ```

2. **Capture host keys.** On each host read `/etc/ssh/ssh_host_ed25519_key.pub`
   and paste it into [secrets/secrets.nix](secrets/secrets.nix), replacing the
   matching placeholder (`dream` / `framework`).

3. **Create the secret.** Hash the real password, then encrypt it. The agenix CLI
   is already on `PATH` (itera installs it):

   ```sh
   mkpasswd -m sha-512                       # copy the resulting hash
   cd secrets
   agenix -e lcleveland-password.age         # paste the hash, save, quit
   cd ..
   git add secrets/lcleveland-password.age secrets/secrets.nix
   ```

4. **Re-enable and rebuild.** Uncomment the two lines disabled in install step 4,
   then:

   ```sh
   sudo nixos-rebuild switch --flake .#dream   # or: sudo nh os switch
   ```

   Confirm: `ls -l /run/agenix/lcleveland-password` exists and
   `getent shadow lcleveland` shows a hash. Commit the changes.

## Rebuild

`itera.nix.nh.flake` points at this checkout, so after install:

```sh
sudo nh os switch
```

## Notes

- `nix flake check` / eval requires `secrets/lcleveland-password.age` to exist.
  Before it is created, temporarily comment out the `secrets.secrets` and
  `hashedPasswordFile` lines in [hosts/common.nix](hosts/common.nix).
- Eiros hardware workarounds (dream MT7927 initrd timeout, Framework MT7922
  Bluetooth quirks) were intentionally **not** carried over.
