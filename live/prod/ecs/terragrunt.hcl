terraform {
  source = "../../../modules/ecs"
}

include {
  path = find_in_parent_folders()
}

dependency "vpc" {
  config_path = "../vpc"
}

inputs = {
  environment         = "prod"
  vpc_id              = dependency.vpc.outputs.vpc_id
  public_subnet_ids   = dependency.vpc.outputs.public_subnets
  private_subnet_ids  = dependency.vpc.outputs.private_subnets
  region              = "sa-east-1"
}
