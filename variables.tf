variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
  sensitive   = true
}

variable "aws_availability_zone" {
  type        = string
  default     = "us-east-1a"
  description = "Availability zone for Lightsail instance"
  sensitive   = true
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Zone ID for Cloudflare domain"
  sensitive   = true
}
