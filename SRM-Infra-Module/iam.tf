##################
# IAM role + Instance profile for SSM (Session Manager)
##################
resource "aws_iam_role" "ec2_role" {
  name = "srms-ec2-role-single"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
# An AWS IAM Instance Profile is a 
# container for an IAM role that you can use to pass role information to an EC2 instance when the instance starts.
# without storing the long term credentials on the instance.

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "srms-ec2-profile-single"
  role = aws_iam_role.ec2_role.name
}