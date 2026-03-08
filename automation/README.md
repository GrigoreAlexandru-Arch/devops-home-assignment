# Self-Hosted Sentry Deployment

This project automates the provisioning and configuration of a self-hosted Sentry instance on AWS. It uses Terraform to create the underlying infrastructure and Ansible to deploy and configure the Sentry Docker Compose stack.

## Architecture Overview

- **Infrastructure:** AWS EC2 instance (Ubuntu 24.04) running in a default VPC.
- **Networking:** Application Load Balancer (ALB) listening on HTTPS (443) using a self-signed certificate, forwarding traffic to the EC2 instance on HTTP (9000).
- **Security:** Security groups restrict direct access. SSH (22) is limited to a specified IP, and web traffic (9000) is restricted to the ALB.
- **Application:** Sentry v26.2.1 deployed via Docker Compose.

## Project Structure

```text
project/
├── terraform/
│   ├── main.tf
│   └── variables.tf
└── ansible/
    ├── deploy-sentry.yml
    ├── inventory.ini
    └── vault.yml

```

## Prerequisites

- **Terraform:** Version 1.14.6 or later.
- **Ansible:** Installed on the deployment machine.
- **AWS CLI:** Configured with appropriate credentials and permissions.
- **SSH Key:** A public key located at `~/.ssh/sentry_aws_key.pub`.

## Deployment Instructions

### 1. Provision Infrastructure (Terraform)

Navigate to the `terraform` directory and apply the configuration. You will need to provide values for your variables (e.g., `aws_region`, `ssh_allowed_ip`, `instance_type`, `volume_size`, 'ssh_key_path').

```bash
cd project/terraform
terraform init
terraform apply

```

After a successful apply, Terraform will output two values:

- `sentry_public_ip`: Use this to update your Ansible `inventory.ini`.
- `sentry_alb_dns`: The URL used to access the Sentry web interface.

### 2. Configure Ansible Vault

Ensure your **`ansible/vault.yml`** file contains the required credentials for the Sentry administrator account. Encrypt this file using `ansible-vault`.

Required variables inside `vault.yml`:

- `vault_sentry_admin_email`
- `vault_sentry_admin_password`

```bash
ansible-vault encrypt ../ansible/vault.yml

```

### 3. Update Inventory

Update `project/ansible/inventory.ini` with the `sentry_public_ip` output from Terraform under the `[sentry_servers]` group. Ensure the `ansible_user` is set to `ubuntu`.

### 4. Deploy Sentry (Ansible)

From the `terraform` directory, execute the Ansible playbook. This command automatically injects the ALB DNS name into the Ansible run for CSRF configuration.

```bash
ansible-playbook -i ../ansible/inventory.ini ../ansible/deploy-sentry.yml --ask-vault-pass -e "alb_dns_name=$(terraform output -raw sentry_alb_dns)"

```

### 5. Access Sentry

Once the Ansible playbook completes successfully, wait a few minutes for the Sentry Docker containers to fully initialize. Access the Sentry web interface by navigating to the ALB DNS name provided by the Terraform output using `https://`.

> **Note:** Because the ALB uses a self-signed certificate, your browser will display a security warning. You must bypass this warning to access the login page.
