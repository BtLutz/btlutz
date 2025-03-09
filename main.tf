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
  egress = []
}

resource "aws_launch_template" "btlutz" {
  name_prefix   = "ecs-template"
  image_id      = "ami-08b5b3a93ed654d19"
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.btlutz.id]
  iam_instance_profile {
    name = "ecsInstanceRole"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      volume_type = "gp2"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ecs-instance"
    }
  }

  user_data = filebase64("${path.module}/ecs.sh")
}

resource "aws_autoscaling_group" "btlutz" {
  vpc_zone_identifier = [aws_subnet.btlutz_a.id, aws_subnet.btlutz_b.id]
  desired_capacity    = 1
  max_size            = 1
  min_size            = 1

  launch_template {
    id      = aws_launch_template.btlutz.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
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
resource "aws_ecs_capacity_provider" "btlutz" {
  name = "btlutz"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.btlutz.arn

    managed_scaling {
      maximum_scaling_step_size = 1000
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 1
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "btlutz" {
  cluster_name = aws_ecs_cluster.btlutz.name

  capacity_providers = [aws_ecs_capacity_provider.btlutz.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.btlutz.name
  }
}

resource "aws_ecs_task_definition" "btlutz" {
  family             = "btlutz"
  network_mode       = "awsvpc"
  execution_role_arn = "arn:aws:iam::372340059345:role/ecsTaskExecutionRole"
  cpu                = 256
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([
    {
      name      = "dockergs"
      image     = "public.ecr.aws/f9n5f1l7/dgs:latest"
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

  network_configuration {
    subnets         = [aws_subnet.btlutz_a.id, aws_subnet.btlutz_b.id]
    security_groups = [aws_security_group.btlutz.id]
  }

  force_new_deployment = true

  triggers = {
    redeployment = timestamp()
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.btlutz.name
    weight            = 100
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.btlutz.arn
    container_name   = "dockergs"
    container_port   = 80
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = false
  }

  depends_on = [aws_autoscaling_group.btlutz]
}
