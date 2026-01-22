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

####################
# ALB and Target Group
####################

resource "aws_lb" "app_alb" {
  name               = "srms-app-alb-${var.project_suffix}"
  load_balancer_type = "application"
  subnets            = [aws_subnet.main.id, aws_subnet.public_2.id]
  security_groups    = [aws_security_group.alb_sg.id]
  enable_deletion_protection = false

  tags = {
    Name = "srms-app-alb-${var.project_suffix}"
  }
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
  name     = "srms-app-tg-${var.project_suffix}"
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