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

provider "aws" {
  region = "us-east-1" # Set the AWS region to US East (N. Virginia)
}

resource "aws_ecr_repository" "btlutz" {
  name = "btlutz"
}

resource "aws_ecs_cluster" "btlutz" {
  name = "btlutz"
}

resource "aws_security_group" "web-sg" {
  name = "btlutz-sg"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress = []
}

resource "aws_ecs_task_definition" "btlutz" {
  family       = "btlutz"
  network_mode = "host"
  container_definitions = jsonencode([
    {
      name      = "btlutz"
      image     = "${aws_ecr_repository.btlutz.repository_url}:latest"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
      }]
  }])
}

resource "aws_ecs_service" "btlutz" {
  name            = "btlutz"
  cluster         = aws_ecs_cluster.btlutz.id
  task_definition = aws_ecs_task_definition.btlutz.arn
  desired_count   = 1
  deployment_circuit_breaker {
    enable   = true
    rollback = false
  }
}
