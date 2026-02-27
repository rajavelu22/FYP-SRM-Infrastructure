variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}
variable "project_suffix" {
  description = "Short unique suffix for resource names (e.g. fyp, dev, v1)"
  type        = string
  default     = "fyp"
}


### Compute part
variable "asg_min_size" {
  type    = number
  default = 1
}
variable "asg_desired_capacity" {
  type    = number
  default = 3
}
variable "asg_max_size" {
  type    = number
  default = 5
}
variable "ssh_allowed_cidr" {
  description = "CIDR allowed to SSH into instances (use your IP e.g. 203.0.113.5/32). Leave empty to allow 0.0.0.0/0 (NOT recommended)."
  type        = string
  default     = "0.0.0.0/0"
}
variable "app_repo_url" {
  description = "Repo URL to clone (used by user_data). Replace with your repo if needed."
  type        = string
  default     = "https://github.com/rajavelu22/SRM-FYP.git"
}

variable "asg_instance_type" {
  description = "Instance type for autoscaled instances"
  type        = string
  default     = "t3.medium"
}