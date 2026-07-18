# agenix recipients file. Lists the PUBLIC keys allowed to decrypt each secret:
# each host's ed25519 public key (for on-machine decryption at activation) plus an
# optional personal admin key so the secret can be edited from either machine.
#
# The placeholders below must be filled in after each host's first boot — read
# /etc/ssh/ssh_host_ed25519_key.pub on the machine — then re-encrypt with:
#   nix run github:ryantm/agenix -- -r     # rekey existing .age files
let
  # Host keys — replace with the real values from each machine.
  dream = "ssh-ed25519 AAAA...REPLACE_ME dream-host-key";
  framework = "ssh-ed25519 AAAA...REPLACE_ME framework-host-key";

  # Optional personal key used only to edit/rekey secrets (not required to decrypt
  # on the hosts). Drop it if unused.
  admin = "ssh-ed25519 AAAA...REPLACE_ME lcleveland@personal";

  allHosts = [
    dream
    framework
    admin
  ];
in
{
  "lcleveland-password.age".publicKeys = allHosts;
}
