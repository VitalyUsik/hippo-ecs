remote_state {
  backend = "s3"
  config = {
    bucket         = "hellohippo-state-bucket"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "sa-east-1"
    dynamodb_table = "terraform-lock-table"
  }
}
