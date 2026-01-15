terraform {
  source = "../terraform"
}

inputs = {
  aws_region   = "us-east-1"
  name_prefix  = "james-ubuntu-gui"
  instance_type = "t3.large"
  root_volume_gb = 80
  allowed_cidr = "0.0.0.0/0"
  use_spot = true
  spot_max_price = ""

  dev_username = "dev"
  # Set via environment variable to avoid committing secrets:
  # export TF_VAR_rdp_password="..."
  # or use a Terragrunt locals + read_terragrunt_config if you prefer.
  # rdp_password = "CHANGE_ME"
}
