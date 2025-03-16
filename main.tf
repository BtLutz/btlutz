terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws" # Specify the source of the AWS provider
      version = "~> 4.0"        # Use a version of the AWS provider that is compatible with version
    }
    random = {
      source  = "hashicorp/random"
      version = "3.4.3"
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

resource "aws_iam_role" "ECSTaskExecutionRole" {

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Environment = "aws-ia-fargate"
  }
}
resource "aws_vpc" "btlutz" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    name = "btlutz"
  }
}

resource "aws_subnet" "btlutz_a" {
  vpc_id                  = aws_vpc.btlutz.id
  cidr_block              = cidrsubnet(aws_vpc.btlutz.cidr_block, 8, 1)
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
}

resource "aws_subnet" "btlutz_b" {
  vpc_id                  = aws_vpc.btlutz.id
  cidr_block              = cidrsubnet(aws_vpc.btlutz.cidr_block, 8, 2)
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
}

resource "aws_internet_gateway" "btlutz" {
  vpc_id = aws_vpc.btlutz.id
  tags = {
    Name = "aws_internet_gateway"
  }
}

resource "aws_route_table" "aws_route_table" {
  vpc_id = aws_vpc.btlutz.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.btlutz.id
  }
}

resource "aws_route_table_association" "btlutz_a" {
  subnet_id      = aws_subnet.btlutz_a.id
  route_table_id = aws_route_table.aws_route_table.id
}

resource "aws_route_table_association" "btlutz_b" {
  subnet_id      = aws_subnet.btlutz_b.id
  route_table_id = aws_route_table.aws_route_table.id
}

resource "aws_security_group" "btlutz" {
  name   = "aws_security_group"
  vpc_id = aws_vpc.btlutz.id

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

resource "aws_lb" "btlutz" {
  name               = "btlutz"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.btlutz.id]
  subnets            = [aws_subnet.btlutz_a.id, aws_subnet.btlutz_b.id]

  tags = {
    Name = "btlutz"
  }
}

resource "aws_lb_target_group" "btlutz" {
  name        = "btlutz"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.btlutz.id

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "ecs_alb_listener" {
  load_balancer_arn = aws_lb.btlutz.arn
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
  execution_role_arn       = aws_iam_role.ECSTaskExecutionRole.arn
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
      image     = "${aws_ecr_repository.btlutz.repository_url}:latest"
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
    subnets         = [aws_subnet.btlutz_a.id, aws_subnet.btlutz_b.id]
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
