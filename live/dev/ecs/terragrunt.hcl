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
  environment         = "dev"
  vpc_id              = dependency.vpc.outputs.vpc_id
  public_subnet_ids   = dependency.vpc.outputs.public_subnet_ids
  private_subnet_ids  = dependency.vpc.outputs.private_subnet_ids
  region              = "sa-east-1"
}
