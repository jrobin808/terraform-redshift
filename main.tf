variable "aws_region" {}

variable "rs_cluster_identifier" {}

variable "rs_database_name" {}

variable "rs_master_username" {}

variable "rs_master_pass" {}

variable "rs_nodetype" {}

variable "rs_cluster_type" {}

variable "vpc_cidr" {}

variable "redshift_subnet_cidr_1" {}

variable "redshift_subnet_cidr_2" {}

variable "deployed_by" {}

variable "environment" {}


# data "aws_iam_policy_document" "kms_use" {
#   statement {
#     sid = "Allow KMS Use"
#     effect = "Allow"
#     actions = [
#       "kms:GenerateDataKey",
#       "kms:Decrypt",
#       "kms:DescribeKey",
#     ]
#     resources = [
#         "${aws_redshift_cluster.arn}"
#     ]
#   }
#   depends_on = [
#     aws_redshift_cluster.default
#   ]
# }

locals {
  common_tags = {
    environment = "${var.environment}"
    deployed_by       = "${var.deployed_by}"
    managed-by  = "Terraform"
  }
}

output "donttagmebro" {
  value = local.common_tags

}
provider "aws" {
  region = var.aws_region
}

data "aws_default_tags" "local" {}

# Creating a AWS secret for database master account (Masteraccoundb)

resource "aws_secretsmanager_secret" "secretmasterDB" {
  name = var.rs_master_username
}

# Creating a AWS secret versions for database master account (Masteraccoundb)

resource "aws_secretsmanager_secret_version" "sversion" {
  secret_id     = aws_secretsmanager_secret.secretmasterDB.id
  secret_string = <<EOF
   {
    "username": "${var.rs_master_username}"
    "password": "${var.rs_master_pass}"
   }
EOF
}

resource "aws_vpc" "redshift_vpc" {
  cidr_block       = var.vpc_cidr
  instance_tenancy = "default"

  tags = merge(
    local.common_tags,
    { "Name" = "redshift-vpc" }
  )
}

resource "aws_internet_gateway" "redshift_vpc_gw" {
  vpc_id = aws_vpc.redshift_vpc.id
  
  tags = merge(
    local.common_tags,
    { "Name" = "redshift-vpc" }
  )

  depends_on = [
    aws_vpc.redshift_vpc
  ]
}

resource "aws_subnet" "redshift_subnet_1" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = var.redshift_subnet_cidr_1
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = "true"

  tags = merge(
    local.common_tags,
    { "Name" = "redshift-subnet-1" }
  )

  depends_on = [
    aws_vpc.redshift_vpc
  ]
}

resource "aws_subnet" "redshift_subnet_2" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = var.redshift_subnet_cidr_2
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = "true"


  tags = merge(
    local.common_tags,
    { "Name" = "redshift-subnet-2" }
  )

  depends_on = [
    aws_vpc.redshift_vpc
  ]
}

resource "aws_redshift_subnet_group" "redshift_subnet_group" {
  name       = "redshift-subnet-group"
  subnet_ids = ["${aws_subnet.redshift_subnet_1.id}", "${aws_subnet.redshift_subnet_2.id}"]

  tags = merge(
    local.common_tags,
    { "Name" = "redshift-subnet-group" }
  )
}

resource "aws_default_security_group" "redshift_security_group" {
  vpc_id = aws_vpc.redshift_vpc.id

  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    { "Name" = "redshift-sg" }
  )

  depends_on = [
    aws_vpc.redshift_vpc
  ]
}

resource "aws_iam_role_policy" "s3_full_access_policy" {
  name = "redshift_s3_policy"
  role = aws_iam_role.redshift_role.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_role" "redshift_role" {
  name = "redshift_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "redshift.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
  tags = merge(
    local.common_tags,
    { "Name" = "redshift-role" }
  )
}

resource "aws_redshift_cluster" "default" {
  cluster_identifier        = var.rs_cluster_identifier
  database_name             = var.rs_database_name
  master_username           = var.rs_master_username
  master_password           = var.rs_master_pass
  node_type                 = var.rs_nodetype
  cluster_type              = var.rs_cluster_type
  cluster_subnet_group_name = aws_redshift_subnet_group.redshift_subnet_group.id
  skip_final_snapshot       = true
  iam_roles                 = ["${aws_iam_role.redshift_role.arn}"]

  depends_on = [
    aws_vpc.redshift_vpc,
    aws_default_security_group.redshift_security_group,
    aws_redshift_subnet_group.redshift_subnet_group,
    aws_iam_role.redshift_role
  ]

  tags = merge(
    local.common_tags,
    { "Name" = "${var.rs_database_name}" }
  )

}


