variable "project_suffix" {
  description = "Short unique suffix for resource names (e.g. fyp, dev, v1)"
  type        = string
  default     = "fyp"
}
variable "ssh_allowed_cidr" {
  description = "CIDR allowed to SSH into instances (use your IP e.g. 203.0.113.5/32). Leave empty to allow 0.0.0.0/0 (NOT recommended)."
  type        = string
  default     = "0.0.0.0/0"
}