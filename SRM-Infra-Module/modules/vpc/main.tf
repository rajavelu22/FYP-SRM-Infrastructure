##################
# VPC / Subnet / IGW / Route Table
##################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "srms-single-vpc" }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true # make subnet public so instances get public IPs

  tags = { Name = "srms-single-subnet" }
}

# vpc.tf - create a second public subnet (different AZ) and associate with public route table

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24" # change if needed
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags                    = { Name = "srms-public-subnet-2" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "srms-igw" }
}

# Public route table: route all internet traffic (0.0.0.0/0) to IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = { Name = "srms-public-rt" }
}

resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Associate the public route table with the subnet
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.public.id
}

data "aws_availability_zones" "available" {
  state = "available"
}


##################
# IAM role + Instance profile for SSM (Session Manager)
##################
resource "aws_iam_role" "ec2_role" {
  name = "srms-ec2-role-${var.project_suffix}"

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
  name = "srms-ec2-profile-${var.project_suffix}"
  role = aws_iam_role.ec2_role.name
}
