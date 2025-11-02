####################
# AMI lookup (Ubuntu 22.04)
####################
data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

####################
# Launch Template
####################

resource "aws_launch_template" "app_lt" {
  name_prefix   = "srms-lt-"
  image_id      = data.aws_ami.ubuntu_2204.id
  instance_type = var.asg_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  vpc_security_group_ids = [aws_security_group.ec2_sg_for_alb.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail
    exec > /var/log/user-data.log 2>&1

    # install docker & docker-compose plugin (simple approach)
    apt-get update -y
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release git software-properties-common

    if ! command -v docker >/dev/null 2>&1; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
      apt-get update -y
      apt-get install -y docker-ce docker-ce-cli containerd.io
    fi

    systemctl enable --now docker

    if [ ! -f /usr/local/lib/docker/cli-plugins/docker-compose ]; then
      mkdir -p /usr/local/lib/docker/cli-plugins
      curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose
      chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    fi

    REPO_DIR="/home/ubuntu/SRM-FYP"
    RUN_AS_USER="ubuntu"

    # Clone repo (idempotent) — Terraform variable is used directly for the repo URL
    if [ -d "$${REPO_DIR}" ]; then
      cd "$${REPO_DIR}"
      sudo -u $${RUN_AS_USER} git pull origin main || true
    else
      mkdir -p /home/ubuntu
      sudo -u $${RUN_AS_USER} git clone "${var.app_repo_url}" "$${REPO_DIR}" || true
    fi

    chown -R $${RUN_AS_USER}:$${RUN_AS_USER} "$${REPO_DIR}" || true
    chmod -R u+rwX "$${REPO_DIR}" || true

    # create systemd unit for docker compose
    cat > /etc/systemd/system/srm-fyp-stack.service <<'SERVICE'
    [Unit]
    Description=SRM-FYP Docker Compose stack
    After=network.target docker.service
    Requires=docker.service

    [Service]
    Type=oneshot
    WorkingDirectory=/home/ubuntu/SRM-FYP
    TimeoutStartSec=0
    RemainAfterExit=yes
    ExecStart=/usr/bin/docker compose up -d
    ExecStop=/usr/bin/docker compose down
    User=root

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable --now srm-fyp-stack.service || true

    # simple health probe loop
    for i in $(seq 1 30); do
      sleep 5
      if curl -sSf --max-time 2 http://127.0.0.1/ >/dev/null 2>&1; then
        echo "local web returned OK"
        break
      fi
      echo "waiting for local app ($i/30)..."
    done

    echo "userdata complete"
    EOF
  )
}


####################
# Security groups
####################
resource "aws_security_group" "alb_sg" {
  name        = "srms-alb-sg"
  description = "ALB security group - allows HTTP from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  #create ssh access to alb sg
  ingress {
    description = "SSH from admin CIDR (if set)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "srms-alb-sg" }
}

resource "aws_security_group" "ec2_sg_for_alb" {
  name        = "srms-ec2-sg-alb"
  description = "Allow incoming HTTP from ALB only, and optional SSH from admin"
  vpc_id      = aws_vpc.main.id

  # allow HTTP from ALB's security group
  ingress {
    description     = "HTTP from ALB security group"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # optional SSH (restrict to your CIDR if provided)
  ingress {
    description = "SSH from admin CIDR (if set)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidr != "" ? [var.ssh_allowed_cidr] : ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "srms-ec2-sg-alb" }
}
####################
# ALB and Target Group
####################

resource "aws_lb" "app_alb" {
  name               = "srms-app-alb"
  load_balancer_type = "application"
  subnets = [aws_subnet.main.id, aws_subnet.public_2.id]
           # your single public subnet
  security_groups    = [aws_security_group.alb_sg.id]
  enable_deletion_protection = false

  tags = { Name = "srms-app-alb" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "srms-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

####################
# Auto Scaling Group
####################
data "aws_instances" "asg_instances" {
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [aws_autoscaling_group.app_asg.name]
  }
}
resource "aws_autoscaling_group" "app_asg" {
  name                      = "srms-asg"
  max_size                  = var.asg_max_size
  min_size                  = var.asg_min_size
  desired_capacity          = var.asg_desired_capacity
  # vpc_zone_identifier       = [aws_subnet.main.id]
  vpc_zone_identifier = [aws_subnet.main.id, aws_subnet.public_2.id]

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }
  target_group_arns = [aws_lb_target_group.app_tg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "srms-asg-instance"
    propagate_at_launch = true
  }
}

####################
# Target tracking scaling policy (scale on ASG average CPU)
####################
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "srms-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}

####################
# (Optional) legacy single-instance SG kept for compatibility if needed
####################
resource "aws_security_group" "allow_ssh" {
  name        = "allow-ssh-and-app"
  description = "Allow SSH, HTTP, and phpMyAdmin ports"
  vpc_id      = aws_vpc.main.id

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH - restrict to your IP (not 0.0.0.0/0)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidr != "" ? [var.ssh_allowed_cidr] : ["0.0.0.0/0"]
  }

  # phpMyAdmin - restrict to your IP
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidr != "" ? [var.ssh_allowed_cidr] : ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "srms-instance-sg" }
}
