terraform {
  source = "../../../modules/vpc"
}

include {
  path = find_in_parent_folders()
}

inputs = {
  name = "prod-vpc"
  cidr = "10.0.0.0/16"

  region = "sa-east-1"

  azs             = ["sa-east-1a", "sa-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.3.0/24", "10.0.4.0/24"]

  tags = {
    Terraform   = "true"
    Environment = "prod"
  }
}