####################
# Outputs
####################
output "alb_dns" {
  description = "ALB DNS name - use this to access the app"
  value       = aws_lb.app_alb.dns_name
}

output "instance_public_ip" {
  description = "SRM instance public ip"
  value = data.aws_instances.asg_instances.public_ips
}