# Terraform SUSE AI on AWS

This project deploys a complete SUSE AI environment on a single, GPU-enabled AWS EC2 instance. It uses Terraform to provision the infrastructure and a user-data script to install and configure all necessary components.

### Key Features:

* **Automated Infrastructure:** Creates an EC2 instance, allocates an Elastic IP, and configures security groups.
* **DNS Integration:** Automatically creates a DNS A record in Cloudflare pointing your chosen hostname to the instance.
* **Production-Grade Kubernetes:** Deploys **RKE2**, a secure and conformant Kubernetes distribution.
* **GPU Enabled:** Installs the native NVIDIA drivers and the **NVIDIA GPU Operator** with a time-slicing configuration to create 4 virtual GPUs.
* **Full SUSE AI Stack:** Installs Rancher Prime, cert-manager, and the SUSE AI Deployer chart with all its dependencies, configured to leverage the available GPU resources.
* **Simplified Workflow:** Uses `apply.sh` and `destroy.sh` scripts for easy creation, log monitoring, and cleanup.

## Prerequisites

1.  **Terraform:** [Install Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli).
2.  **AWS Account:** An active AWS account.
3.  **AWS CLI:** [Install and configure the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html). This is required for the destroy script to function correctly.
4.  **SUSE Customer Center (SCC) Account:** An active SUSE account with entitlements for Rancher Prime and SUSE AI. You will need your SCC username, a token, and a product registration code.
5.  **Cloudflare Account:** A Cloudflare account managing the domain you wish to use. You will need your Cloudflare API Token and the Zone ID for your domain.
6.  **SSH Key Pair:** An SSH key pair to access the EC2 instance. If you don't have one, create it:
    ```
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/suse-ai-key
    ```

## How to Use

1.  **Prepare the Project Files:**
    Unzip the project zip file. Open a terminal and navigate into the newly created directory.

2.  **Create and Configure `terraform.tfvars`:**
    The project includes an example file. Copy it to create your own configuration:
    ```
    cp terraform.tfvars.example terraform.tfvars
    ```
    Now, open `terraform.tfvars` and fill in **all** the required values. The `destroy.sh` script depends on this file for credentials, so it's the recommended way to manage secrets for this project.

3.  **Make Scripts Executable:**
    ```
    chmod +x apply.sh destroy.sh
    ```

4.  **Deploy the Infrastructure:**
    Run the `apply.sh` script. This single command handles everything:
    ```
    ./apply.sh
    ```
    The script will:
    * Initialize Terraform.
    * Apply the configuration to build all AWS and Cloudflare resources.
    * Once the instance is running, it will automatically connect via SSH and stream the live output of the installation script. This will take 15-25 minutes.

5.  **Access Rancher:**
    Once the installation script finishes (you'll see the "Bootstrap password is: admin" message in the log), you can access Rancher at the hostname you configured:
    * **URL:** `https://<your-rancher-hostname>`
    * **Password:** `admin` (you will be prompted to change this on first login).

6.  **Destroy the Infrastructure:**
    When you are finished, run the `destroy.sh` script to tear down all resources and avoid further costs:
    ```
    ./destroy.sh
    ```
    This script automatically reads credentials from your `terraform.tfvars` file to force-stop the EC2 instance before telling Terraform to terminate all resources.