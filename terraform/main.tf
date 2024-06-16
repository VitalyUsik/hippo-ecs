provider "aws" {
  region = var.region
}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_ecr_repository" "nginx" {
  name                 = "${var.environment}-nginx-repo"
  image_tag_mutability = "MUTABLE"
}

resource "null_resource" "docker_build" {
  provisioner "local-exec" {
    command = "bash ./docker_build.sh ${aws_ecr_repository.nginx.repository_url} ${data.aws_region.current.name}"
  }

  # Ensure the Docker build runs before deploying ECS
  triggers = {
    always_run = "${timestamp()}"
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "main_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, 0)
}

resource "aws_subnet" "main_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, 1)
}

resource "aws_security_group" "main" {
  vpc_id = aws_vpc.main.id

  ingress {
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

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.environment}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "main_1" {
  subnet_id      = aws_subnet.main_1.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "main_2" {
  subnet_id      = aws_subnet.main_2.id
  route_table_id = aws_route_table.main.id
}


resource "aws_lb" "main" {
  name               = "main-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.main.id]
  subnets            = [aws_subnet.main_1.id, aws_subnet.main_2.id]
}

resource "aws_lb_target_group" "main" {
  name        = "main-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.environment}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_cluster" "main" {
  name = "${var.environment}-cluster"
}

resource "aws_ecs_task_definition" "main" {
  family                   = "${var.environment}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name      = "nginx"
    image     = "${aws_ecr_repository.nginx.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 80
      hostPort      = 80
      protocol      = "tcp"
    }]
  }])

  depends_on = [null_resource.docker_build]
}

resource "aws_ecs_service" "main" {
  name            = "${var.environment}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.main_1.id, aws_subnet.main_2.id]
    security_groups = [aws_security_group.main.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "nginx"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.http_listener]
}

resource "aws_route53_record" "www" {
  count = var.domain_name != "" ? 1 : 0
  zone_id = "your-zone-id"
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.ecr.dkr"
  subnet_ids        = [aws_subnet.main_1.id, aws_subnet.main_2.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]
  vpc_endpoint_type = "Interface"
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.ecr.api"
  subnet_ids        = [aws_subnet.main_1.id, aws_subnet.main_2.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]
  vpc_endpoint_type = "Interface"
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.region}.s3"
  route_table_ids = [aws_route_table.main.id]
  vpc_endpoint_type = "Gateway"
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.secretsmanager"
  subnet_ids        = [aws_subnet.main_1.id, aws_subnet.main_2.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]
  vpc_endpoint_type = "Interface"
}
