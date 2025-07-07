# main.tf

# Specify required provider sources
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4"
    }
  }
}

# Configure the AWS provider
provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# Configure the Cloudflare provider
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Allocate an Elastic IP for the instance
resource "aws_eip" "suse_ai_eip" {
  instance = aws_instance.suse_ai_node.id
  domain   = "vpc"
}

# Create a new key pair
resource "aws_key_pair" "deployer_key" {
  key_name   = "suse-ai-deployer-key"
  public_key = file(var.public_key_path)
}

# Create a security group to allow web and SSH traffic
resource "aws_security_group" "suse_ai_sg" {
  name        = "suse-ai-sg"
  description = "Allow web and SSH traffic for SUSE AI"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch the EC2 instance
resource "aws_instance" "suse_ai_node" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer_key.key_name
  security_groups = [aws_security_group.suse_ai_sg.name]

  root_block_device {
    volume_size = var.root_volume_size
  }

  # Pass the required variables to the installation script template.
  user_data = templatefile("${path.module}/install_suse_ai.sh.tpl", {
    scc_username            = var.scc_username,
    scc_token               = var.scc_token,
    rancher_hostname        = var.rancher_hostname,
    open_webui_hostname     = var.open_webui_hostname,
    suse_registration_code  = var.suse_registration_code
  })

  tags = {
    Name = "SUSE-AI-Node"
  }

  # This provisioner runs when `terraform destroy` is called.
  # It will force a stop on the instance before Terraform terminates it.
  # Note: This requires the AWS CLI to be installed and configured on the machine running Terraform.
  provisioner "local-exec" {
    when    = destroy
    # We derive the region from the instance's availability_zone to avoid an invalid reference.
    # The AWS CLI will use the ambient credentials from your shell, so the environment block is not needed.
    command = "aws ec2 stop-instances --instance-ids ${self.id} --force --region ${substr(self.availability_zone, 0, length(self.availability_zone) - 1)}"
  }
}

# Create a DNS A record in Cloudflare for Rancher
resource "cloudflare_record" "rancher_dns" {
  # Only create this record if a hostname is provided
  count           = var.rancher_hostname != "" ? 1 : 0
  zone_id         = var.cloudflare_zone_id
  name            = var.rancher_hostname
  content         = aws_eip.suse_ai_eip.public_ip
  type            = "A"
  ttl             = 300
  proxied         = false
  allow_overwrite = true # This will overwrite any existing record with the same name
}

# Create a DNS A record in Cloudflare for Open WebUI
resource "cloudflare_record" "open_webui_dns" {
  # Only create this record if a hostname is provided
  count           = var.open_webui_hostname != "" ? 1 : 0
  zone_id         = var.cloudflare_zone_id
  name            = var.open_webui_hostname
  content         = aws_eip.suse_ai_eip.public_ip
  type            = "A"
  ttl             = 300
  proxied         = false
  allow_overwrite = true # This will overwrite any existing record with the same name
}


# Output the public IP of the instance
output "suse_ai_public_ip" {
  value = aws_eip.suse_ai_eip.public_ip
}

output "suse_ai_public_dns" {
  value = aws_instance.suse_ai_node.public_dns
}
