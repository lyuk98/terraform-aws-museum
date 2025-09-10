terraform {
  backend "s3" {
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    region                      = "us-west-002"

    use_path_style = true
    key            = "terraform-aws-museum.tfstate"
  }
}

# Create a Tailscale OAuth client
resource "tailscale_oauth_client" "museum" {
  description = "museum"
  scopes      = ["auth_keys"]
  tags        = ["tag:museum", "tag:webserver"]
}

# Add a public SSH key
resource "aws_lightsail_key_pair" "museum" {
  name = "museum-key-pair"
}

# Create a Lightsail instance
resource "aws_lightsail_instance" "museum" {
  name              = "museum"
  availability_zone = var.aws_availability_zone
  blueprint_id      = "debian_12"
  bundle_id         = "small_3_0"
  key_pair_name     = aws_lightsail_key_pair.museum.name
  user_data         = "cp /home/admin/.ssh/authorized_keys /root/.ssh/authorized_keys"
}

# Open instance ports
resource "aws_lightsail_instance_public_ports" "museum" {
  instance_name = aws_lightsail_instance.museum.name

  # SSH
  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
  }

  # HTTPS
  port_info {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
  }

  # Tailscale
  port_info {
    protocol  = "udp"
    from_port = 41641
    to_port   = 41641
  }
}

# Encryption key for Museum
resource "random_bytes" "encryption_key" {
  length = 32
}

resource "random_bytes" "encryption_hash" {
  length = 64
}

# JWT secrets
resource "random_bytes" "jwt_secret" {
  length = 32
}

# Write secret containing connection details
resource "vault_kv_secret" "museum" {
  path = "kv/ente/aws/museum"
  data_json = jsonencode({
    key = {
      encryption = random_bytes.encryption_key.base64
      hash       = random_bytes.encryption_hash.base64
    }
    jwt = {
      secret = random_bytes.jwt_secret.base64
    }
  })
}

# Prepare policy document
data "vault_policy_document" "museum" {
  rule {
    path         = "kv/ente/b2/ente-b2"
    capabilities = ["read"]
    description  = "Allow access to secrets for object storage"
  }
  rule {
    path         = "kv/ente/scaleway/ente-scaleway-postgres"
    capabilities = ["read"]
    description  = "Allow access to PostgreSQL credentials"
  }
  rule {
    path         = "kv/ente/cloudflare/certificate"
    capabilities = ["read"]
    description  = "Allow access to TLS certificate data"
  }
  rule {
    path         = vault_kv_secret.museum.path
    capabilities = ["read"]
    description  = "Allow access to credentials for Museum"
  }
}

# Write policy allowing Museum to read secrets
resource "vault_policy" "museum" {
  name   = "museum"
  policy = data.vault_policy_document.museum.hcl
}

# Mount AppRole auth backend
data "vault_auth_backend" "approle" {
  path = "approle"
}

# Create an AppRole for Museum to retrieve secrets with
resource "vault_approle_auth_backend_role" "museum" {
  backend        = data.vault_auth_backend.approle.path
  role_name      = "museum"
  token_policies = ["museum"]
}

# Create a SecretID for the Vault AppRole
resource "vault_approle_auth_backend_role_secret_id" "museum" {
  backend   = vault_approle_auth_backend_role.museum.backend
  role_name = vault_approle_auth_backend_role.museum.role_name
}

# Build the NixOS system configuration
module "nixos_system" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "github:lyuk98/nixos-config#nixosConfigurations.museum.config.system.build.toplevel"
}

# Build the NixOS partition layout
module "nixos_partitioner" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "github:lyuk98/nixos-config#nixosConfigurations.museum.config.system.build.diskoScript"
}

# Install NixOS to Lightsail instance
module "nixos_install" {
  source = "github.com/nix-community/nixos-anywhere//terraform/install"

  nixos_system      = module.nixos_system.result.out
  nixos_partitioner = module.nixos_partitioner.result.out

  target_host     = aws_lightsail_instance.museum.public_ip_address
  target_user     = aws_lightsail_instance.museum.username
  ssh_private_key = aws_lightsail_key_pair.museum.private_key

  instance_id = aws_lightsail_instance.museum.public_ip_address

  extra_files_script = "${path.module}/deploy-secrets.sh"
  extra_environment = {
    MODULE_PATH                   = path.module
    VAULT_ROLE_ID                 = vault_approle_auth_backend_role.museum.role_id
    VAULT_SECRET_ID               = vault_approle_auth_backend_role_secret_id.museum.secret_id
    TAILSCALE_OAUTH_CLIENT_ID     = tailscale_oauth_client.museum.id
    TAILSCALE_OAUTH_CLIENT_SECRET = tailscale_oauth_client.museum.key
  }
}

# Get Cloudflare Zone information
data "cloudflare_zone" "ente" {
  zone_id = var.cloudflare_zone_id
}

# A record for Ente accounts
resource "cloudflare_dns_record" "accounts" {
  name    = "ente-accounts"
  ttl     = 1
  type    = "A"
  zone_id = data.cloudflare_zone.ente.zone_id
  content = aws_lightsail_instance.museum.public_ip_address
  proxied = true
}

# A record for Ente cast
resource "cloudflare_dns_record" "cast" {
  name    = "ente-cast"
  ttl     = 1
  type    = "A"
  zone_id = data.cloudflare_zone.ente.zone_id
  content = aws_lightsail_instance.museum.public_ip_address
  proxied = true
}

# A record for Ente albums
resource "cloudflare_dns_record" "albums" {
  name    = "ente-albums"
  ttl     = 1
  type    = "A"
  zone_id = data.cloudflare_zone.ente.zone_id
  content = aws_lightsail_instance.museum.public_ip_address
  proxied = true
}

# A record for Ente photos
resource "cloudflare_dns_record" "photos" {
  name    = "ente-photos"
  ttl     = 1
  type    = "A"
  zone_id = data.cloudflare_zone.ente.zone_id
  content = aws_lightsail_instance.museum.public_ip_address
  proxied = true
}

# A record for Ente API (Museum)
resource "cloudflare_dns_record" "api" {
  name    = "ente-api"
  ttl     = 1
  type    = "A"
  zone_id = data.cloudflare_zone.ente.zone_id
  content = aws_lightsail_instance.museum.public_ip_address
  proxied = true
}

# AAAA record for Ente accounts
resource "cloudflare_dns_record" "accounts_aaaa" {
  name    = "ente-accounts"
  ttl     = 1
  type    = "AAAA"
  zone_id = data.cloudflare_zone.ente.zone_id
  content = aws_lightsail_instance.museum.ipv6_addresses[0]
  proxied = true
}

# AAAA record for Ente cast
resource "cloudflare_dns_record" "cast_aaaa" {
  name    = "ente-cast"
  ttl     = 1
  type    = "AAAA"
  zone_id = data.cloudflare_zone.ente.zone_id
  content = aws_lightsail_instance.museum.ipv6_addresses[0]
  proxied = true
}

# AAAA record for Ente albums
resource "cloudflare_dns_record" "albums_aaaa" {
  name    = "ente-albums"
  ttl     = 1
  type    = "AAAA"
  zone_id = data.cloudflare_zone.ente.zone_id
  content = aws_lightsail_instance.museum.ipv6_addresses[0]
  proxied = true
}

# AAAA record for Ente photos
resource "cloudflare_dns_record" "photos_aaaa" {
  name    = "ente-photos"
  ttl     = 1
  type    = "AAAA"
  zone_id = data.cloudflare_zone.ente.zone_id
  content = aws_lightsail_instance.museum.ipv6_addresses[0]
  proxied = true
}

# AAAA record for Ente API (Museum)
resource "cloudflare_dns_record" "api_aaaa" {
  name    = "ente-api"
  ttl     = 1
  type    = "AAAA"
  zone_id = data.cloudflare_zone.ente.zone_id
  content = aws_lightsail_instance.museum.ipv6_addresses[0]
  proxied = true
}
