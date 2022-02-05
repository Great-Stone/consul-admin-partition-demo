terraform {
  required_version = ">= 0.13"
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = var.tags
  }
}

data "aws_caller_identity" "current" {}

resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name                            = "tf-example",
    "kubernetes.io/cluster/gs-cluster-0" = "shared",
    "kubernetes.io/cluster/gs-cluster-1" = "shared",
  }
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = data.aws_availability_zones.available.names.0
  map_public_ip_on_launch = true
  tags = {
    "kubernetes.io/cluster/gs-cluster-0" = "shared",
    "kubernetes.io/cluster/gs-cluster-1" = "shared",
  }
}

resource "aws_subnet" "sub" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.40.0/24"
  availability_zone       = data.aws_availability_zones.available.names.1
  map_public_ip_on_launch = true
  tags = {
    "kubernetes.io/cluster/gs-cluster-0" = "shared",
    "kubernetes.io/cluster/gs-cluster-1" = "shared",
  }
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.my_vpc.id
}

data "aws_ami" "al2" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }
}

resource "aws_key_pair" "bar" {
  key_name   = "gs-key"
  public_key = file(var.publickey_file)
}

resource "aws_security_group" "bar" {
  name_prefix = "gs-terraform"
  vpc_id      = aws_vpc.my_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  ingress {
    from_port   = 8500
    to_port     = 8500
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  ingress {
    from_port   = 8501
    to_port     = 8501
    protocol    = "tcp"
    cidr_blocks = [var.my_ip, aws_vpc.my_vpc.cidr_block]
  }
  ingress {
    from_port   = 8300
    to_port     = 8300
    protocol    = "ALL"
    cidr_blocks = [aws_vpc.my_vpc.cidr_block]
  }
  ingress {
    from_port   = 8301
    to_port     = 8301
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.my_vpc.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_default_route_table" "example" {
  default_route_table_id = aws_vpc.my_vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id
  }
}

resource "aws_route_table_association" "example" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_default_route_table.example.id
}

resource "aws_eip" "example" {
  vpc = true
}

resource "aws_eip" "server" {
  vpc      = true
  instance = aws_instance.server.id
}

resource "aws_instance" "server" {
  ami           = data.aws_ami.al2.id
  subnet_id     = aws_subnet.main.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.bar.key_name

  vpc_security_group_ids = [
    aws_security_group.bar.id
  ]

  tags = {
    type = "consul-server"
  }
}

#AWS EKS
module "eks" {
  count  = 2
  source = "terraform-aws-modules/eks/aws"

  cluster_name                    = "${var.prefix}-cluster-${count.index}"
  cluster_version                 = "1.21"
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  vpc_id                    = aws_vpc.my_vpc.id
  subnet_ids                = [aws_subnet.main.id, aws_subnet.sub.id]
  cluster_security_group_id = aws_security_group.bar.id

  eks_managed_node_group_defaults = {
    ami_type               = "AL2_x86_64"
    disk_size              = 50
    instance_types         = ["m5.large"]
    vpc_security_group_ids = [aws_security_group.bar.id]
  }

  eks_managed_node_groups = {
    test = {
      min_size     = 1
      max_size     = 1
      desired_size = 1

      instance_types = ["m5.large"]
      capacity_type  = "SPOT"
      labels = {
        Environment = "test"
        GithubRepo  = "terraform-aws-eks"
        GithubOrg   = "terraform-aws-modules"
      }
    }
  }
}

resource "null_resource" "add_kube_context" {
  depends_on = [
    module.eks
  ]

  provisioner "local-exec" {
    # Load credentials to local environment so subsequent kubectl commands can be run
    command = <<EOS
aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.0.cluster_id} --profile default;
aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.1.cluster_id} --profile default;
EOS
  }
}