variable "project_id" { type = string }
variable "region" { type = string default = "us-central1" }
variable "zone" { type = string default = "us-central1-a" }

variable "name_prefix" { type = string default = "ubuntu-gui" }
variable "machine_type" { type = string default = "e2-standard-2" } # 2 vCPU, 8 GB
variable "boot_disk_gb" { type = number default = 80 }
variable "allowed_cidr" { type = string default = "0.0.0.0/0" }
variable "use_spot" { type = bool default = true }

variable "dev_username" { type = string default = "dev" }
variable "rdp_password" { type = string sensitive = true }

# Software versions (configurable)
variable "git_version" { type = string default = "2.39.2" }
variable "python_version" { type = string default = "3.11.13" }
variable "node_version" { type = string default = "v23.5.0" }
variable "npm_version" { type = string default = "11.6.0" }
variable "docker_version_prefix" { type = string default = "28.4.0" }
variable "awscli_version" { type = string default = "2.32.16" }
variable "psql_major" { type = number default = 16 }
variable "cursor_channel" { type = string default = "stable" }
