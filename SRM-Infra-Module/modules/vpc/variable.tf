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