#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

if [[ $# -ne 1 ]]; then
    printf 'Usage: bash %s "ssh-ed25519 BASE64 [comment]"\n' "${0##*/}" >&2
    exit 2
fi

export LC_ALL=C
public_key=${1%$'\r'}
key_pattern='^ssh-ed25519[[:blank:]]+[A-Za-z0-9+/]{68}([[:blank:]]+.*)?$'
if [[ $public_key == *$'\n'* || $public_key == *$'\r'* ||
      ${#public_key} -ge 8192 || ! $public_key =~ $key_pattern ]]; then
    fail 'Pass one complete ssh-ed25519 public key line from your .pub file.'
fi

command -v ssh-keygen >/dev/null || fail 'OpenSSH ssh-keygen is required.'
key_info=$(ssh-keygen -l -E sha256 -f /dev/stdin <<< "$public_key" 2>/dev/null) ||
    fail 'OpenSSH could not read this Ed25519 public key.'
read -r _ fingerprint _ <<< "$key_info"

[[ ${HOME:-} == /* && -d $HOME && -O $HOME ]] ||
    fail 'Run this as the account that should receive the key, with its own home directory.'
umask 077
ssh_dir=$HOME/.ssh
authorized_keys=$ssh_dir/authorized_keys
lock_dir=$ssh_dir/.install-ssh-key.lock

[[ ! -L $ssh_dir ]] || fail '.ssh is a symbolic link.'
mkdir -p -- "$ssh_dir"
[[ -d $ssh_dir && -O $ssh_dir ]] || fail 'The current account must own .ssh.'
chmod 700 -- "$ssh_dir"

mkdir -- "$lock_dir" 2>/dev/null || fail 'Unable to acquire the key installation lock.'
trap 'rmdir -- "$lock_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ ! -L $authorized_keys ]] || fail 'authorized_keys is a symbolic link.'
if [[ -e $authorized_keys ]]; then
    [[ -f $authorized_keys && -O $authorized_keys ]] ||
        fail 'authorized_keys must be a regular file owned by the current account.'
else
    : > "$authorized_keys"
fi
chmod 600 -- "$authorized_keys"

# Fingerprint comparison also recognizes keys that already have login restrictions.
if ssh-keygen -l -E sha256 -f "$authorized_keys" 2>/dev/null |
    awk -v wanted="$fingerprint" '$2 == wanted { found = 1 } END { exit !found }'; then
    printf 'This public key is already present in %s.\n' "$authorized_keys"
    exit 0
fi

# Keep the previous entry intact if the file ends without a newline.
last_byte=$(tail -c 1 -- "$authorized_keys")
separator=
if [[ -n $last_byte ]]; then
    separator=$'\n'
fi
printf '%s%s\n' "$separator" "$public_key" >> "$authorized_keys"
printf 'Public key added to %s.\n' "$authorized_keys"
