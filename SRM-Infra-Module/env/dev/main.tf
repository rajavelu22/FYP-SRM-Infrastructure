terraform {
  backend "s3" {
    bucket         = "rajavelu-terraform-state"
    key            = "alb-project/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source   = "../../modules/vpc"
  vpc_cidr = var.vpc_cidr

  subnet_cidr = var.subnet_cidr
}

module "alb" {
  source            = "../../modules/alb"
  vpc_id            = module.vpc.vpc_id
  ssh_allowed_cidr  = var.ssh_allowed_cidr
  project_suffix    = var.project_suffix
  public_subnet_ids = module.vpc.public_subnet_ids
}

module "compute" {
  source                                    = "../../modules/compute"
  vpc_id                                    = module.vpc.vpc_id
  project_suffix                            = var.project_suffix
  asg_instance_type                         = var.asg_instance_type
  asg_min_size                              = var.asg_min_size
  asg_max_size                              = var.asg_max_size
  asg_desired_capacity                      = var.asg_desired_capacity
  ssh_allowed_cidr                          = var.ssh_allowed_cidr
  app_repo_url                              = var.app_repo_url
  aws_iam_instance_profile_ec2_profile_name = module.vpc.aws_iam_instance_profile_ec2_profile_name
  aws_lb_target_group_arns                  = module.alb.aws_lb_target_group_arns
  public_subnet_ids                         = module.vpc.public_subnet_ids
  alb_sg_id     = module.alb.alb_sg_id
}
