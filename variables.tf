# variables.tf

variable "aws_region" {
  description = "The AWS region to deploy to."
  type        = string
  default     = "us-east-1"
}

variable "aws_access_key" {
  description = "Your AWS access key."
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "Your AWS secret key."
  type        = string
  sensitive   = true
}

variable "scc_username" {
  description = "Your SUSE Customer Center (SCC) username (or service account username)."
  type        = string
  sensitive   = true
}

variable "scc_token" {
  description = "Your SUSE Customer Center (SCC) token (or service account token)."
  type        = string
  sensitive   = true
}

variable "suse_registration_code" {
  description = "Your SUSE product registration code."
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Your Cloudflare API token."
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "The Zone ID of your domain in Cloudflare."
  type        = string
}

variable "ami_id" {
  description = "The AMI ID for the SUSE instance. Ensure it's a SLES 15 SP4 or SP5 based image."
  type        = string
}

variable "instance_type" {
  description = "The EC2 instance type."
  type        = string
  default     = "t3a.xlarge" # SUSE AI requires a minimum of 4 vCPUs and 16GB RAM
}

variable "root_volume_size" {
  description = "The size of the root block device in GiB."
  type        = number
  default     = 50
}

variable "public_key_path" {
  description = "Path to your SSH public key file (e.g., ~/.ssh/id_rsa.pub)."
  type        = string
}

variable "private_key_path" {
  description = "Path to your SSH private key file (e.g., ~/.ssh/id_rsa)."
  type        = string
}

variable "rancher_hostname" {
  description = "The fully qualified domain name (FQDN) for the Rancher server. Required for Cloudflare integration."
  type        = string
}
