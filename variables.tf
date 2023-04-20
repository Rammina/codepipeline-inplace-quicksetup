variable "region" {
  type    = string
  default = "us-east-1"
}

variable "subnet_count" {
  description = "Number of public subnets to create"
  type        = number
  default     = 2
}

variable "alb_name" {
  type    = string
  default = "whatevername-alb"
}

variable "target_group_name" {
  type    = string
  default = "alb-target-group"
}

variable "log_bucket_name" {
  type    = string
  default = "whatevername-alb-logs"
}

variable "launch_template_name_prefix" {
  type    = string
  default = "web-server"
}

variable "web_server_role_name" {
  type    = string
  default = "web_server_role"
}

variable "asg_lt_sg_name" {
  type    = string
  default = "asg_security_group"
}

variable "asg_name" {
  type    = string
  default = "web_server_asg"
}

variable "asg_min_size" {
  description = "The minimum size of the ASG"
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "The desired capacity of the ASG"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "The maximum size of the ASG"
  type        = number
  default     = 3
}

variable "codecommit_repo_name" {
  type    = string
  default = "simple_code_commit_repo"
}

variable "cd_app_name" {
  type    = string
  default = "test-codedeploy-app"
}

variable "cd_deployment_group_name" {
  type    = string
  default = "test-deployment-group"
}

variable "codepipeline_name" {
  type    = string
  default = "test-pipeline"
}

variable "artifact_bucket_name" {
  type    = string
  default = "whatevername-codepipeline-artifact-store"
}
