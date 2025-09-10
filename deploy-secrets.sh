#!/usr/bin/env bash

install --directory --mode 751 persist/var/lib/secrets

secrets_dir="$MODULE_PATH/secrets"
mkdir --parents "$secrets_dir"

echo -n $VAULT_ROLE_ID > "$secrets_dir/vault-role-id"
echo -n $VAULT_SECRET_ID > "$secrets_dir/vault-secret-id"
echo -n $TAILSCALE_OAUTH_CLIENT_ID > "$secrets_dir/tailscale-oauth-client-id"
echo -n $TAILSCALE_OAUTH_CLIENT_SECRET > "$secrets_dir/tailscale-oauth-client-secret"

install --mode 600 \
  "$secrets_dir/vault-role-id" \
  "$secrets_dir/vault-secret-id" \
  "$secrets_dir/tailscale-oauth-client-id" \
  "$secrets_dir/tailscale-oauth-client-secret" \
  persist/var/lib/secrets
