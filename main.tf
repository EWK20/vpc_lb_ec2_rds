terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.67"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.4"
    }
  }
  required_version = ">= 1.2.0"
}


#* Variables
variable "region" {
  type    = string
  default = "us-east-1"
}
variable "internet_cidr_block" {
  type    = string
  default = "0.0.0.0/0"
}
variable "vpc_details" {
  type = object({
    cidr_block = string
    name       = string
  })
}
variable "public_subnet" {
  type = map(any)
}
variable "private_subnet" {
  type = map(any)
}
variable "rtb_name" {
  type = string
}
variable "key_details" {
  type = map(any)
}
variable "authorized_ip" {
  type = list(string)
}
variable "webserver_details" {
  type = object({
    ami           = string
    instance_type = string
    name          = string
    user_data     = string
  })
}
variable "autoscaling_details" {
  type = object({
    name               = string
    desired            = number
    min                = number
    max                = number
    availability_zones = list(string)
  })
}
variable "bastion_details" {
  type = object({
    ami           = string
    instance_type = string
    name          = string
  })
}
variable "rds_details" {
  type = object({
    engine            = string
    identifier        = string
    allocated_storage = number
    engine_version    = string
    instance_class    = string
    username          = string
    password          = string
  })
}


provider "aws" {
  region = var.region
}


#! PART A

#* Create virtual network (VPC)
resource "aws_vpc" "custom_vpc" {
  cidr_block           = var.vpc_details.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = var.vpc_details.name
  }
}

#* Create public subnets in zone 1a and 1b
resource "aws_subnet" "public_subnet" {
  for_each                = var.public_subnet
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = each.value.cidr_block
  map_public_ip_on_launch = true
  availability_zone       = each.value.availability_zone
  tags = {
    Name = each.value.name
  }
}

#* Create private subnets in zone 1a and 1b
resource "aws_subnet" "private_subnet" {
  for_each          = var.private_subnet
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone
  tags = {
    Name = each.value.name
  }
}

#* Create internet gateway (IGW)
resource "aws_internet_gateway" "custom_igw" {
  vpc_id = aws_vpc.custom_vpc.id
}

#* Create new route table and add route for igw to internet
resource "aws_route_table" "custom_route_table" {
  vpc_id = aws_vpc.custom_vpc.id

  route {
    cidr_block = var.internet_cidr_block
    gateway_id = aws_internet_gateway.custom_igw.id
  }

  tags = {
    Name = var.rtb_name
  }
}

#* Associate the new route table with the public subnets
resource "aws_route_table_association" "public_rtb_association" {
  for_each       = var.public_subnet
  subnet_id      = aws_subnet.public_subnet[each.key].id
  route_table_id = aws_route_table.custom_route_table.id
}


#! PART B

#* Create an SSH key for web servers
resource "tls_private_key" "server_keys" {
  for_each  = var.key_details
  algorithm = "RSA"
  rsa_bits  = 4096
}

#* Save webserver SSH private key in local file
resource "local_file" "server_key_save" {
  for_each        = var.key_details
  content         = tls_private_key.server_keys[each.key].private_key_pem
  filename        = "${each.value.name}.pem"
  file_permission = "0400"
}

#* Register public keys with AWS
resource "aws_key_pair" "register_public_key" {
  for_each   = var.key_details
  key_name   = each.value.name
  public_key = tls_private_key.server_keys[each.key].public_key_openssh
}

#* Create security group for bastion server group
resource "aws_security_group" "bastion_sg" {
  name        = "Bastion_SG"
  description = "Allows bastion servers to be accessed by an authorized ip"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.authorized_ip
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.internet_cidr_block]
  }

  tags = {
    Name = "Bastion SG"
  }
}

#* Create security group for web server group
resource "aws_security_group" "webserver_sg" {
  name        = "WebServer_SG"
  description = "Allows web servers to be accessed"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
    description     = "Allow SSH from bastion servers"
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.internet_cidr_block]
    description = "Allow HTTP from internet"
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.internet_cidr_block]
    description = "Allow ICMP from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.internet_cidr_block]
  }

  tags = {
    Name = "WebServer SG"
  }
}

#* Create security group for load balancer
resource "aws_security_group" "webserver_lb_sg" {
  name        = "WebServer_LB_SG"
  description = "Allows web servers load balancer to be accessed"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.internet_cidr_block]
    description = "Allow HTTP from internet"
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.internet_cidr_block]
    description = "Allow ICMP from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.internet_cidr_block]
  }

  tags = {
    Name = "WebServer LB SG"
  }
}

#* Create a launch template
resource "aws_launch_template" "webserver_template" {
  image_id               = var.webserver_details.ami
  instance_type          = var.webserver_details.instance_type
  key_name               = aws_key_pair.register_public_key["webserver"].key_name
  vpc_security_group_ids = [aws_security_group.webserver_sg.id]
  user_data              = filebase64(var.webserver_details.user_data)
  name                   = "WebServerTemplate"
}

#* Create load balancer target group
resource "aws_lb_target_group" "webserver_target_group" {
  name     = "webserver-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.custom_vpc.id
}

#* Create auto scaling group for web servers
resource "aws_autoscaling_group" "webserver_asg" {
  name                      = var.autoscaling_details.name
  vpc_zone_identifier       = [for public_subnet in aws_subnet.public_subnet : public_subnet.id]
  desired_capacity          = var.autoscaling_details.desired
  min_size                  = var.autoscaling_details.min
  max_size                  = var.autoscaling_details.max
  target_group_arns         = [aws_lb_target_group.webserver_target_group.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  launch_template {
    id      = aws_launch_template.webserver_template.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = var.webserver_details.name
    propagate_at_launch = true
  }
  lifecycle {
    ignore_changes = [load_balancers, target_group_arns]
  }
}

#* Create application load balancer
resource "aws_lb" "webserver_alb" {
  name               = "webserver-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.webserver_lb_sg.id]
  subnets            = [for public_subnet in aws_subnet.public_subnet : public_subnet.id]
}

#* Create listener for alb
resource "aws_lb_listener" "webserver_alb_listener" {
  load_balancer_arn = aws_lb.webserver_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webserver_target_group.arn
  }
}

#* Create a new ALB Target Group attachment
resource "aws_autoscaling_attachment" "webserver_asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.webserver_asg.id
  lb_target_group_arn    = aws_lb_target_group.webserver_target_group.arn
}

#* Create bastion server
resource "aws_instance" "bastion_server" {
  ami                    = var.bastion_details.ami
  instance_type          = var.bastion_details.instance_type
  key_name               = aws_key_pair.register_public_key["bastion"].key_name
  subnet_id              = aws_subnet.public_subnet["public1"].id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  tags = {
    Name = var.bastion_details.name
  }
}


#! PART C

#* Create db subnet group
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db_subnet_group"
  subnet_ids = [for priv_subnet in aws_subnet.private_subnet : priv_subnet.id]
  tags = {
    Name = "DB Subnet Group"
  }
}

#* Create a security group for RDS Database Instance
resource "aws_security_group" "database_sg" {
  name        = "database_sg"
  description = "Allows database servers to be accessed by authorized ips and web servers"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.authorized_ip
  }
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.webserver_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.internet_cidr_block]
  }
}

#* Create RDS instance
resource "aws_db_instance" "database" {
  engine                 = var.rds_details.engine
  identifier             = var.rds_details.identifier
  allocated_storage      = var.rds_details.allocated_storage
  engine_version         = var.rds_details.engine_version
  instance_class         = var.rds_details.instance_class
  username               = var.rds_details.username
  password               = var.rds_details.password
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.database_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
}





