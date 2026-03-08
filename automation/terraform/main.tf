terraform {
  required_version = "1.14.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.35.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.2.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "sentry_alb_sg"
  description = "Allow HTTPS to ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "sentry_sg" {
  name        = "sentry_web_and_ssh"
  description = "Allow SSH from local machine IP and HTTP/HTTPS for Sentry"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from local machine"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_ip]
  }

  ingress {
    description     = "Sentry Web UI from ALB"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  owners = ["099720109477"]
}

resource "aws_key_pair" "sentry_key" {
  key_name   = "sentry-deployer-key"
  public_key = file(var.ssh_key_path)
}

resource "aws_instance" "sentry_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.sentry_sg.id]
  key_name                    = aws_key_pair.sentry_key.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
  }

  tags = {
    Name = "Self-Hosted-Sentry-VM"
  }
}

resource "tls_private_key" "alb_cert_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "alb_cert" {
  private_key_pem = tls_private_key.alb_cert_key.private_key_pem

  subject {
    common_name  = "sentry.internal"
    organization = "Development"
  }

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "alb_cert" {
  private_key      = tls_private_key.alb_cert_key.private_key_pem
  certificate_body = tls_self_signed_cert.alb_cert.cert_pem
}

resource "aws_lb" "sentry_alb" {
  name               = "sentry-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "sentry_tg" {
  name     = "sentry-tg"
  port     = 9000
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/_health/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.sentry_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.alb_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sentry_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "sentry_attachment" {
  target_group_arn = aws_lb_target_group.sentry_tg.arn
  target_id        = aws_instance.sentry_server.id
  port             = 9000
}

output "sentry_public_ip" {
  description = "The public IP address of the Sentry VM (Use this in your Ansible inventory for SSH)"
  value       = aws_instance.sentry_server.public_ip
}

output "sentry_alb_dns" {
  description = "The DNS name of the Load Balancer (Access Sentry here via HTTPS)"
  value       = aws_lb.sentry_alb.dns_name
}
