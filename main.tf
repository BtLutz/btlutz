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

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_security_group" "btlutz" {
  name   = "aws_security_group"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    self        = "false"
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
  name               = "btlutz"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.btlutz.id]
  subnets            = [aws_default_subnet.default_subnet_a.id, aws_default_subnet.default_subnet_b.id, aws_default_subnet.default_subnet_c.id]

  tags = {
    Name = "btlutz"
  }
}

resource "aws_lb_target_group" "btlutz" {
  name        = "btlutz"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_default_vpc.default_vpc.id

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "ecs_alb_listener" {
  load_balancer_arn = aws_alb.btlutz.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.btlutz.arn
  }
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
      image     = "${aws_ecr_repository.btlutz.repository_url}:71a02ca4a111e41b21cc2796631213e0fd7e7c59"
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
    subnets         = [aws_default_subnet.default_subnet_a.id, aws_default_subnet.default_subnet_b.id, aws_default_subnet.default_subnet_c.id]
    security_groups = [aws_security_group.btlutz.id]
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
