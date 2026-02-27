output "vpc_id" {
  value = aws_vpc.main.id
}

output "ec2_instance_profile" {
  value = aws_iam_instance_profile.ec2_profile.name
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value = [
    aws_subnet.main.id,
    aws_subnet.public_2.id
  ]
}

output "aws_iam_instance_profile_ec2_profile_name" {
  value = aws_iam_instance_profile.ec2_profile.name
}