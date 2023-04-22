terraform {
  #  backend "s3" {}

  required_providers {
    aws = {
      source  = "registry.terraform.io/hashicorp/aws"
      version = "~> 4.0"
    }

    random = {
      source  = "registry.terraform.io/hashicorp/random"
      version = "~> 3.4"
    }
  }
}

provider "aws" {}
provider "random" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  tags = {
    Tier = "private"
  }
}

resource "random_pet" "cluster_id" {}

resource "aws_elasticache_subnet_group" "target_net" {
  name       = "${random_pet.cluster_id.id}-subnet-group"
  subnet_ids = data.aws_subnets.private.ids
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${random_pet.cluster_id.id}-replication-group"
  description                = "Replication group for ${random_pet.cluster_id.id} redis cluster"
  subnet_group_name          = aws_elasticache_subnet_group.target_net.name
  node_type                  = "cache.t4g.micro"
  engine_version             = "7.0"
  parameter_group_name       = "default.redis7"
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  security_group_ids         = [
    aws_security_group.redis.id
  ]
  user_group_ids = [
    aws_elasticache_user_group.default.id
  ]
}

resource "aws_security_group" "redis" {
  name        = "${random_pet.cluster_id.id}-redis-sg"
  description = "Security group for ${random_pet.cluster_id.id} redis cluster"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "random_pet" "user_name" {
  length    = 1
  separator = ""
}

# Create a deactivated user to be activated with password
# by credentials manager
resource "aws_elasticache_user" "app" {
  user_id              = random_pet.user_name.id
  user_name            = random_pet.user_name.id
  access_string        = "*off* +get ~keys*" // This disable the user
  engine               = "REDIS"
  no_password_required = true
}

# Default user with no rights
resource "aws_elasticache_user" "default" {
  user_id              = "${random_pet.cluster_id.id}-default"
  user_name            = "default"
  access_string        = "*off* +get ~keys*" // This disable the user
  engine               = "REDIS"
  no_password_required = true
}


resource "aws_elasticache_user_group" "default" {
  engine        = "REDIS"
  user_group_id = "${random_pet.cluster_id.id}-default"
  user_ids      = [
    aws_elasticache_user.default.id,
    aws_elasticache_user.app.id
  ]
  lifecycle {
    ignore_changes = [
      user_ids,
    ]
  }
}

resource "aws_secretsmanager_secret" "app_user" {
  name = "ec/${random_pet.cluster_id.id}/users/${random_pet.user_name.id}"
}

resource "aws_secretsmanager_secret_version" "app_user" {
  secret_id     = aws_secretsmanager_secret.app_user.id
  secret_string = jsonencode({
    user_arn = aws_elasticache_user.app.arn
    username = aws_elasticache_user.app.user_name
  })
}

resource "aws_secretsmanager_secret_rotation" "app_user" {
  rotation_lambda_arn = "" // TODO: Add lambda to rotate redis password
  secret_id           = aws_secretsmanager_secret.app_user.id
  rotation_rules {
    automatically_after_days = 30
  }
}

output "REDIS_HOST" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "REDIS_PORT" {
  value = aws_elasticache_replication_group.redis.port
}

output "REDIS_USER" {
  value = random_pet.user_name.id
}

output "REDIS_PASSWORD_ARN" {
  value = aws_secretsmanager_secret.app_user.arn
}
