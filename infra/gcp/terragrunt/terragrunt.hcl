terraform { source = "../terraform" }

inputs = {
  project_id  = "YOUR_GCP_PROJECT_ID"
  region      = "us-central1"
  zone        = "us-central1-a"
  name_prefix = "james-ubuntu-gui"
  machine_type = "e2-standard-2"
  boot_disk_gb = 80
  allowed_cidr = "0.0.0.0/0"
  use_spot = true
  dev_username = "dev"
}
