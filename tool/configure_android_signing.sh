#!/usr/bin/env bash

set -euo pipefail

repository="${SUPERHEALTH_REPOSITORY:-gaduffl/SuperHealth}"
default_backup_dir="${HOME}/SuperHealth-signing"

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "'$1' is required."
}

read_secret_twice() {
  local label="$1"
  local first second
  read -r -s -p "$label: " first
  printf '\n' >&2
  read -r -s -p "Confirm $label: " second
  printf '\n' >&2
  [ "$first" = "$second" ] || fail "The values did not match."
  [ "${#first}" -ge 16 ] || fail "$label must contain at least 16 characters."
  REPLY="$first"
}

require_command gh
require_command keytool
require_command base64

gh auth status >/dev/null 2>&1 || fail "Authenticate GitHub CLI first with 'gh auth login'."
gh repo view "$repository" >/dev/null 2>&1 || fail "Cannot access $repository with the current GitHub account."

printf 'SuperHealth Android signing setup\n'
printf 'Repository: %s\n\n' "$repository"
printf '1) Generate a new dedicated SuperHealth key (recommended)\n'
printf '2) Use an existing Android signing keystore\n'
read -r -p 'Choose 1 or 2: ' mode

case "$mode" in
  1)
    read -r -p "Secure backup directory [$default_backup_dir]: " backup_dir
    backup_dir="${backup_dir:-$default_backup_dir}"
    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir"
    keystore_path="${backup_dir}/superhealth-upload.jks"
    [ ! -e "$keystore_path" ] || fail "$keystore_path already exists; move it or choose another directory."

    read -r -p 'Key alias [superhealth]: ' key_alias
    key_alias="${key_alias:-superhealth}"
    read_secret_twice 'Keystore password'
    store_password="$REPLY"
    read_secret_twice 'Key password'
    key_password="$REPLY"

    keytool -genkeypair \
      -keystore "$keystore_path" \
      -storetype JKS \
      -alias "$key_alias" \
      -keyalg RSA \
      -keysize 4096 \
      -validity 10000 \
      -dname 'CN=SuperHealth, OU=Personal Health, O=SuperHealth, C=DE' \
      -storepass "$store_password" \
      -keypass "$key_password" >/dev/null
    chmod 600 "$keystore_path"
    ;;
  2)
    read -r -p 'Absolute path to the existing .jks/.keystore file: ' keystore_path
    [ -f "$keystore_path" ] || fail "Keystore not found: $keystore_path"
    read -r -p 'Key alias: ' key_alias
    [ -n "$key_alias" ] || fail 'A key alias is required.'
    read -r -s -p 'Keystore password: ' store_password
    printf '\n' >&2
    read -r -s -p 'Key password: ' key_password
    printf '\n' >&2
    ;;
  *)
    fail 'Choose either 1 or 2.'
    ;;
esac

keytool -list \
  -keystore "$keystore_path" \
  -alias "$key_alias" \
  -storepass "$store_password" >/dev/null || fail 'The keystore, alias, or password is invalid.'

printf '\nInstalling encrypted GitHub Actions secrets...\n'
base64 < "$keystore_path" | tr -d '\n' | gh secret set ANDROID_KEYSTORE_BASE64 --repo "$repository"
printf '%s' "$key_alias" | gh secret set ANDROID_KEY_ALIAS --repo "$repository"
printf '%s' "$key_password" | gh secret set ANDROID_KEY_PASSWORD --repo "$repository"
printf '%s' "$store_password" | gh secret set ANDROID_STORE_PASSWORD --repo "$repository"

unset key_password store_password REPLY

printf '\nSigning secrets configured for %s.\n' "$repository"
printf 'Permanent keystore: %s\n' "$keystore_path"
printf 'Back up that file and its passwords separately. Never commit the keystore.\n'
printf 'Return to the SuperHealth PR and rerun the Flutter workflow.\n'
