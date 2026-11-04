#!/usr/bin/env bash
# Create or migrate the single environment Basic-auth account without resetting passwords.
set -euo pipefail
[[ $# == 1 || ( $# == 2 && "$2" == --sync-password ) ]] || { echo 'Usage: environment-auth.sh <runtime-directory> [--sync-password]' >&2; exit 2; }
RUNTIME=$1
SYNC_PASSWORD=${2:-}
# Credential rotation is explicit; normal deployment must preserve existing hashes.
if [[ -n "$SYNC_PASSWORD" && ! -s "$RUNTIME/access-password" ]]; then
  echo 'Password synchronization requires a non-empty runtime/access-password; credentials left unchanged' >&2
  exit 1
fi
umask 077
mkdir -p "$RUNTIME"
TEMP=$(mktemp "$RUNTIME/.htpasswd.XXXXXX")
trap 'rm -f "$TEMP"' EXIT
if [[ -s "$RUNTIME/htpasswd" ]]; then
  # Reject ambiguous/unknown accounts rather than overwrite a customized credential file.
  awk -F: '
    NF != 2 || ($1 != "admin" && $1 != "clawlibrary") || $2 == "" { invalid = 1 }
    { count++; hash = $2 }
    END {
      if (invalid || count != 1) exit 1;
      print "admin:" hash;
    }
  ' "$RUNTIME/htpasswd" > "$TEMP" || {
    echo 'Expected one admin or clawlibrary account in runtime/htpasswd; credentials left unchanged' >&2
    exit 1
  }
else
  # A password the owner already set must survive first-time credential generation too.
  if [[ ! -s "$RUNTIME/access-password" ]]; then
    openssl rand -hex 18 > "$RUNTIME/access-password"
  fi
  HASH=$(openssl passwd -apr1 -stdin < "$RUNTIME/access-password")
  printf 'admin:%s\n' "$HASH" > "$TEMP"
fi
if [[ -n "$SYNC_PASSWORD" ]]; then
  # Validate the account above before changing its password. Never log the secret
  # or pass it on the command line, where other processes could read it.
  HASH=$(openssl passwd -apr1 -stdin < "$RUNTIME/access-password")
  printf 'admin:%s\n' "$HASH" > "$TEMP"
fi
# Atomic replacement also guarantees restrictive permissions on migrated files.
mv -f "$TEMP" "$RUNTIME/htpasswd"
