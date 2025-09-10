terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.11"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.9"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.21"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.2"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "cloudflare" {}

provider "random" {}

provider "tailscale" {
  scopes = ["oauth_keys", "auth_keys"]
}

provider "vault" {}
