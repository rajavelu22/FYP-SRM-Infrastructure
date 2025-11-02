# terraform {
#   required_providers {
#     aws = {
#       source  = "hashicorp/aws"
#       version = "~> 5.0"
#     }
#   }
# }

# provider "aws" {
#   region = var.region
# }

# # -----------------------------------------------------------
# # Security Group: allow SSH, HTTP (80), phpMyAdmin (9090)
# # -----------------------------------------------------------
# resource "aws_security_group" "allow_ssh" {
#   name        = "allow-ssh-and-app"
#   description = "Allow HTTP and optional SSH/phpMyAdmin (restrict SSH & phpMyAdmin)"
#   vpc_id      = aws_vpc.main.id        # <-- IMPORTANT: link SG to your VPC

#   # HTTP (public)
#   ingress {
#     from_port   = 80
#     to_port     = 80
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   # SSH - restrict to your IP, not 0.0.0.0/0
#   ingress {
#     from_port   = 22
#     to_port     = 22
#     protocol    = "tcp"
#     cidr_blocks = [var.ssh_allowed_cidr]   # set this in variables.tf to your IP e.g. "203.0.113.5/32"
#     description = "SSH from admin only"
#   }

#   # phpMyAdmin: avoid opening to the world. If you must, restrict to your IP.
#   ingress {
#     from_port   = 9090
#     to_port     = 9090
#     protocol    = "tcp"
#     cidr_blocks = [var.ssh_allowed_cidr]   # limit to your IP for testing
#     description = "phpMyAdmin (restricted)"
#   }
#   ingress = {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = [var.ssh_allowed_cidr]
#   }
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = { Name = "srms-instance-sg" }
# }
# # -----------------------------------------------------------
# # Key Pair: your SSH public key (pass via variable)
# # -----------------------------------------------------------
# resource "aws_key_pair" "tf_key" {
#   key_name   = "terraform-aws-key"
#   public_key = file(var.public_key_path)
# }

# # -----------------------------------------------------------
# # EC2 Instance: Ubuntu with full automation via user_data
# # -----------------------------------------------------------
# resource "aws_instance" "my_instance" {
#   ami                         = "ami-0360c520857e3138f" # Ubuntu 22.04 in us-east-1
#   instance_type               = "t2.medium"
#     iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
#   subnet_id                   = aws_subnet.main.id
#   key_name                    = aws_key_pair.tf_key.key_name
#   vpc_security_group_ids      = [aws_security_group.allow_ssh.id]
#   associate_public_ip_address = true
#   tags = {
#     Name = "SRM-FYP-AutoDeploy"
#   }

#   user_data = <<-EOF
#     #!/bin/bash
#     set -euxo pipefail
#     export PATH=/usr/local/bin:/usr/bin:/bin
#     export DEBIAN_FRONTEND=noninteractive
#     exec > /var/log/user-data.log 2>&1

#     # -------- Basic packages --------
#     apt-get update -y
#     apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release git software-properties-common

#     # -------- Docker install --------
#     if ! command -v docker >/dev/null 2>&1; then
#       curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
#       echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
#         | tee /etc/apt/sources.list.d/docker.list > /dev/null
#       apt-get update -y
#       apt-get install -y docker-ce docker-ce-cli containerd.io
#     fi

#     systemctl enable --now docker

#     # -------- Docker Compose plugin --------
#     if [ ! -f /usr/local/lib/docker/cli-plugins/docker-compose ]; then
#       mkdir -p /usr/local/lib/docker/cli-plugins
#       curl -SL "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-linux-x86_64" \
#         -o /usr/local/lib/docker/cli-plugins/docker-compose
#       chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
#     fi

#     /usr/bin/docker --version || true
#     /usr/bin/docker compose version || true

#     # -------- Clone or update repo --------
#     REPO_DIR="/home/ubuntu/SRM-FYP"
#     REPO_URL="https://github.com/rajavelu22/SRM-FYP.git"

#     if id -u ubuntu >/dev/null 2>&1; then
#       RUN_AS_USER="ubuntu"
#     else
#       RUN_AS_USER="root"
#     fi

#     if [ -d "$${REPO_DIR}" ]; then
#       cd "$${REPO_DIR}"
#       sudo -u $${RUN_AS_USER} git pull origin main || sudo -u $${RUN_AS_USER} git pull --rebase || true
#     else
#       rm -rf "$${REPO_DIR}"
#       mkdir -p /home/ubuntu
#       sudo -u $${RUN_AS_USER} git clone "$${REPO_URL}" "$${REPO_DIR}" || { echo "git clone failed"; exit 1; }
#     fi

#     chown -R $${RUN_AS_USER}:$${RUN_AS_USER} "$${REPO_DIR}" || true
#     chmod -R u+rwX "$${REPO_DIR}" || true

#     # -------- Create systemd service to manage Docker Compose --------
#     cat > /etc/systemd/system/srm-fyp-stack.service <<'SERVICE_EOF'
#     [Unit]
#     Description=SRM-FYP Docker Compose stack
#     After=network.target docker.service
#     Requires=docker.service

#     [Service]
#     Type=oneshot
#     WorkingDirectory=/home/ubuntu/SRM-FYP
#     TimeoutStartSec=0
#     RemainAfterExit=yes
#     ExecStart=/usr/bin/docker compose up -d
#     ExecStop=/usr/bin/docker compose down
#     User=root

#     [Install]
#     WantedBy=multi-user.target
#     SERVICE_EOF

#     systemctl daemon-reload
#     systemctl enable --now srm-fyp-stack.service || true

#     # -------- Wait for DB health --------
#     for i in {1..30}; do
#       if /usr/bin/docker ps --filter "name=srms_db" --filter "health=healthy" --format '{{.Names}}' | grep -q srms_db; then
#         echo "srms_db reported healthy"
#         break
#       fi

#       DB_CID=$(/usr/bin/docker ps --filter "name=srms_db" --format '{{.ID}}' || true)
#       if [ -n "$${DB_CID}" ]; then
#         /usr/bin/docker exec "$${DB_CID}" bash -c "mysqladmin ping -uroot -proot" >/dev/null 2>&1 && { echo "db responded to ping"; break; } || true
#       fi

#       echo "Waiting for DB to be ready (attempt $i)..."
#       sleep 5
#     done

#     # -------- Apache fix (optional) --------
#     APP_CID=$(/usr/bin/docker ps --filter "name=srms_app" --format '{{.ID}}' || true)
#     if [ -n "$${APP_CID}" ]; then
#       /usr/bin/docker exec "$${APP_CID}" bash -c "if [ -w /etc/apache2/apache2.conf ]; then grep -q '^ServerName' /etc/apache2/apache2.conf || echo 'ServerName localhost' >> /etc/apache2/apache2.conf && apache2ctl -k graceful || true; fi" || true
#     fi

#     /usr/bin/docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" > /var/log/docker-ps.out || true
#     echo "user_data finished at $(date)" >> /var/log/user-data.log
#   EOF
# }