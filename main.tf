terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws" # Specify the source of the AWS provider
      version = "~> 4.0"        # Use a version of the AWS provider that is compatible with version
    }
  }
  backend "remote" {
    organization = "TheLonelyGecko"

    workspaces {
      name = "btlutz"
    }
  }
}

locals {
  region = "us-east-1"
}

provider "aws" {
  region = local.region
}

resource "aws_default_vpc" "default_vpc" {}

resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "us-east-1a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "us-east-1b"
}

resource "aws_default_subnet" "default_subnet_c" {
  availability_zone = "us-east-1c"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_execution_role_policy" {
  role = aws_iam_role.ecs_task_execution_role.name
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_security_group" "btlutz" {
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = -1
    security_groups = [aws_security_group.aws_alb_security_group.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "aws_alb_security_group" {
  ingress {
    description = "entry port"
    from_port   = 80
    to_port     = 80
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

resource "aws_alb" "btlutz" {
  load_balancer_type = "application"
  security_groups    = [aws_security_group.aws_alb_security_group.id]
  subnets            = [aws_default_subnet.default_subnet_a.id, aws_default_subnet.default_subnet_b.id, aws_default_subnet.default_subnet_c.id]

}

resource "aws_lb_target_group" "btlutz" {
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_default_vpc.default_vpc.id

  health_check {
    path = ""
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_alb.btlutz.arn
  port              = 443
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  protocol          = "HTTPS"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.btlutz.arn
  }

  certificate_arn = aws_acm_certificate.https.arn
}

resource "aws_ecr_repository" "btlutz" {
  name = "btlutz"
}

resource "aws_ecs_cluster" "btlutz" {
  name = "btlutz"
}

resource "aws_ecs_task_definition" "btlutz" {
  family                   = "btlutz"
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  cpu                      = 256
  memory                   = 512
  requires_compatibilities = ["FARGATE"]

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([
    {
      name      = "btlutz"
      image     = "public.ecr.aws/ecs-sample-image/amazon-ecs-sample:latest"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
      }]
  }])
}

resource "aws_ecs_service" "btlutz" {
  name            = "btlutz"
  cluster         = aws_ecs_cluster.btlutz.id
  task_definition = aws_ecs_task_definition.btlutz.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_default_subnet.default_subnet_a.id, aws_default_subnet.default_subnet_b.id, aws_default_subnet.default_subnet_c.id]
    assign_public_ip = true
    security_groups  = [aws_security_group.btlutz.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.btlutz.arn
    container_name   = "btlutz"
    container_port   = 80
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = false
  }
}

resource "aws_route53_zone" "primary" {
  name = "btlutz.com"
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "btlutz.com"
  type    = "A"
  alias {
    name                   = aws_alb.btlutz.dns_name
    zone_id                = aws_alb.btlutz.zone_id
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate" "https" {
  domain_name       = "btlutz.com"
  validation_method = "DNS"
}

resource "aws_route53_record" "https" {
  for_each = {
    for dvo in aws_acm_certificate.https.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.primary.zone_id
}

resource "aws_acm_certificate_validation" "btlutz" {
  certificate_arn         = aws_acm_certificate.https.arn
  validation_record_fqdns = [for record in aws_route53_record.https : record.fqdn]
}
