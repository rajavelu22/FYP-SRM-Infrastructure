output "instance_public_ips" {
  description = "Public IPs of instances in the Auto Scaling Group"
  value       = data.aws_instances.asg_instances.public_ips
}
