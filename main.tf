# This Terraform config file does the following:

# - Defines AWS provider and Terraform version requirements
# - Fetches available AZs and AMIs 

# - Creates an Application Load Balancer (ALB) to route traffic to EC2 instances
# - Creates an S3 bucket to store ALB logs 
# - Creates a VPC, subnets, internet gateway, and route tables
# - Creates security groups for the ALB and EC2 instances
# - Creates an EC2 launch template to spin up EC2 instances 
# - Creates an IAM role and instance profile for the EC2 instances
# - Creates an Auto Scaling group using the launch template 

# - Creates a CodeCommit repo to store source code
# - Creates a CodeDeploy app and deployment group to deploy to the ASG 
# - Creates a CodePipeline to build and deploy from the CodeCommit repo 
# - Creates IAM roles for CodeDeploy and CodePipeline with appropriate permissions
# - Creates an S3 bucket as an artifact store for CodePipeline
# - Attaches IAM policies to the CodePipeline role to access S3, CodeCommit and EC2

# Terraform and AWS provider required versions
terraform {
  required_version = ">= 1.2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
}

# AWS region to deploy resources to
provider "aws" {
  region = var.region
}

# Fetches the available AWS AZs in the specified region 
data "aws_availability_zones" "available" {
  state = "available"
}

# Fetch the latest Amazon Linux 2 AMI image
data "aws_ami" "amazon_linux" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Defines a template file with a user data script that will be used to launch EC2 instances. 
# The script installs packages, the CodeDeploy agent, and checks that the agent service is running. 
data "template_file" "launch_template_user_data" {
  template = file("${path.module}/scripts/ec2-init.sh")
}

# Public Application Load Balancer to distribute incoming web traffic 
resource "aws_lb" "alb_web" {
  name               = "whatevername-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.lb_security_group.id}"]
  subnets            = aws_subnet.public.*.id

  enable_deletion_protection = false

  access_logs {
    bucket  = aws_s3_bucket.lb_logs.bucket
    prefix  = "whatevername-alb"
    enabled = true
  }
}

# Listener for the ALB to handle HTTP traffic  
resource "aws_lb_listener" "alb_web" {
  load_balancer_arn = aws_lb.alb_web.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_web.arn
  }
}

# Target group for the ALB to forward traffic to 
resource "aws_lb_target_group" "alb_web" {
  name     = "alb-web" # Name of the target group    
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id # Referencing the VPC   
}

# Create an S3 bucket for ALB logs
resource "aws_s3_bucket" "lb_logs" {
  bucket        = "whatevername-alb-logs"
  acl           = "private"
  force_destroy = true
}

# Allow read/write access to the S3 bucket that stores ALB logs   
resource "aws_s3_bucket_policy" "lb_logs_policy" {
  bucket = aws_s3_bucket.lb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:GetObject",
        "s3:GetObjectAcl",
        "s3:DeleteObject"
      ]
      Principal = "*",
      Resource = [
        "${aws_s3_bucket.lb_logs.arn}",
        "${aws_s3_bucket.lb_logs.arn}/*"
      ]
    }]
  })
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Create public subnets
resource "aws_subnet" "public" {
  count                   = 2
  cidr_block              = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  vpc_id                  = aws_vpc.main.id
}

# Create an IGW and attach it to the VPC
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

# Create a public route table and associate it with the subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public.*.id[count.index]
  route_table_id = aws_route_table.public.id
}

# Security group for the load balancer 
resource "aws_security_group" "lb_security_group" {
  name        = "lb_security_group"
  description = "Allow HTTP traffic to load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch template 
resource "aws_launch_template" "web_server_lt" {
  name_prefix   = "web-server"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"

  # user data script for installing the CodeDeploy Agent
  user_data = base64encode(data.template_file.launch_template_user_data.rendered)

  iam_instance_profile {
    name = aws_iam_instance_profile.web_server_profile.name
  }

  vpc_security_group_ids = [aws_security_group.asg_lt_sg.id]

  tags = {
    Environment = "Dev"
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Environment = "Dev"
      Project     = "SimplePipeline"
    }
  }
}

# Create an IAM instance profile for EC2 instances 
resource "aws_iam_instance_profile" "web_server_profile" {
  name = "web_server_instance_profile"
  role = aws_iam_role.web_server_role.name
}

# Create an IAM role for EC2 instances  
resource "aws_iam_role" "web_server_role" {
  name = "web_server_role"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "Service" : "ec2.amazonaws.com"
          },
          "Effect" : "Allow"
        }
      ]
    }
  )
}

# Attach IAM policies to the IAM role
resource "aws_iam_role_policy_attachment" "web_server_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole",
    "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy",
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  ])

  policy_arn = each.value
  role       = aws_iam_role.web_server_role.name
}

# Create a security group for the launch template  
resource "aws_security_group" "asg_lt_sg" {
  name        = "asg_security_group"
  description = "Allow SSH and HTTP traffic"
  vpc_id      = aws_vpc.main.id

  # Allows SSH access from anywhere 
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allows HTTP access from anywhere 
  ingress {
    from_port = 80
    to_port   = 80

    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allows all outbound traffic 
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Auto Scaling Group 
resource "aws_autoscaling_group" "web_server_asg" {
  name                = "web_server_asg"
  min_size            = var.asg_min_size
  desired_capacity    = var.asg_desired_capacity
  max_size            = var.asg_max_size
  vpc_zone_identifier = aws_subnet.public.*.id

  target_group_arns = [aws_lb_target_group.alb_web.arn]
  depends_on        = [aws_lb.alb_web, aws_launch_template.web_server_lt]

  launch_template {
    id      = aws_launch_template.web_server_lt.id
    version = "$Latest"
  }
}

# Create a CodeCommit repository to store source code  
resource "aws_codecommit_repository" "simple_code_commit_repo" {
  repository_name = "simple_code_commit_repo"
  description     = "Repository for the simple code project"
}

# Create a CodeDeploy app and deployment group to deploy to the ASG
resource "aws_codedeploy_app" "cd_app" {
  name = "test-codedeploy-app"
}

# Create a CodeDeploy deployment group
resource "aws_codedeploy_deployment_group" "cd_group" {

  app_name              = aws_codedeploy_app.cd_app.name
  deployment_group_name = "test-deployment-group"
  service_role_arn      = aws_iam_role.codedeploy_role.arn

  # Use traffic control and in-place deployment  
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  # Deploy to the Application Load Balancer target group   
  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.alb_web.name
    }
  }

  # Deploy to the autoscaling group    
  autoscaling_groups = [aws_autoscaling_group.web_server_asg.name]

  # Deploy to instances with these tags
  ec2_tag_set {
    ec2_tag_filter {
      key   = "Environment"
      type  = "KEY_AND_VALUE"
      value = "Dev"
    }

    ec2_tag_filter {
      key   = "Project"
      type  = "KEY_AND_VALUE"
      value = "SimplePipeline"
    }
  }

  # Depends on the ALB target group and ASG existing   
  depends_on = [
    aws_lb_target_group.alb_web,
    aws_autoscaling_group.web_server_asg
  ]
}

# Create CodePipeline pipeline  
resource "aws_codepipeline" "codepipeline" {
  name     = "test-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifact_store.bucket
    type     = "S3"
  }

  # Source stage pulls from CodeCommit repo
  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName = "${aws_codecommit_repository.simple_code_commit_repo.repository_name}"
        BranchName     = "master"
      }
    }
  }

  # Deploy stage uses CodeDeploy to deploy to ASG
  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ApplicationName     = "${aws_codedeploy_app.cd_app.name}"
        DeploymentGroupName = "${aws_codedeploy_deployment_group.cd_group.deployment_group_name}"
      }
    }
  }
}

# IAM role for CodeDeploy 
resource "aws_iam_role" "codedeploy_role" {
  name = "codedeploy-role"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Sid" : "",
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "codedeploy.amazonaws.com"
          },
          "Action" : "sts:AssumeRole"
        }
      ]
  })
}

# Attaches AWS managed policy for CodeDeploy to IAM role 
resource "aws_iam_role_policy_attachment" "AWSCodeDeployRole" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  role       = aws_iam_role.codedeploy_role.name
}

# S3 bucket to store CodePipeline artifacts 
resource "aws_s3_bucket" "artifact_store" {
  bucket        = "whatevername-codepipeline-artifact-store"
  acl           = "private"
  force_destroy = true
}

# IAM role for CodePipeline 
resource "aws_iam_role" "codepipeline_role" {
  name = "test-role"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "Service" : "codepipeline.amazonaws.com"
          },
          "Effect" : "Allow",
          "Sid" : ""
        }
      ]
  })
}

# Attach IAM policies to CodePipeline IAM role
resource "aws_iam_role_policy" "codepipeline_allow_s3_codecommit_ec2" {
  name = "allow_s3_codecommit_ec2"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : [
            "s3:*"
          ],
          "Resource" : [
            "${aws_s3_bucket.artifact_store.arn}",
            "${aws_s3_bucket.artifact_store.arn}/*"
          ],
          "Effect" : "Allow"
        },
        {
          "Action" : [
            "codecommit:*"
          ],
          "Resource" : "${aws_codecommit_repository.simple_code_commit_repo.arn}",
          "Effect" : "Allow"
        },
        {
          "Action" : [
            "ec2:*"
          ],
          "Resource" : "*",
          "Effect" : "Allow"
        },
        {
          "Action" : [
            "codedeploy:*"
          ],
          "Resource" : "*",
          "Effect" : "Allow"
        }
      ]
  })
}
