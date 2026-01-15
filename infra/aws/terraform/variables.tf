variable "aws_region" {
  description = "AWS region (US regions are fine)"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "ubuntu-gui"
}

variable "instance_type" {
  description = "EC2 instance type (hardware configurable). Example: t3.large (2 vCPU, 8 GiB)."
  type        = string
  default     = "t3.large"
}

variable "root_volume_gb" {
  description = "Root EBS volume size (GB)"
  type        = number
  default     = 50
}

variable "allowed_cidr" {
  description = "CIDR allowed to access SSH (22) and RDP (3389). Set to your public IP/32."
  type        = string
  default     = "0.0.0.0/0"
}

variable "use_spot" {
  description = "If true, launch as Spot instance with interruption behavior 'stop' for persistence."
  type        = bool
  default     = true
}

variable "spot_max_price" {
  description = "Optional max Spot price (empty means on-demand cap)."
  type        = string
  default     = ""
}

variable "dev_username" {
  description = "Linux user for SSH + RDP"
  type        = string
  default     = "dev"
}

variable "rdp_password" {
  description = "Password for the dev user (required for RDP). Use a strong password."
  type        = string
  sensitive   = true
}

# --- Software versions (configurable) ---
variable "git_version" {
  description = "Desired git version prefix (best effort). Example: 2.39.2"
  type        = string
  default     = "2.39.2"
}

variable "python_version" {
  description = "Python version to install via pyenv. Example: 3.11.13"
  type        = string
  default     = "3.11.13"
}

variable "node_version" {
  description = "Node.js version to install via nvm. Example: v23.5.0"
  type        = string
  default     = "v23.5.0"
}

variable "npm_version" {
  description = "npm version to install globally. Example: 11.6.0"
  type        = string
  default     = "11.6.0"
}

variable "docker_version_prefix" {
  description = "Docker Engine version prefix (best effort). Example: 28.4.0"
  type        = string
  default     = "28.4.0"
}

variable "awscli_version" {
  description = "AWS CLI v2 version. Example: 2.32.16"
  type        = string
  default     = "2.32.16"
}

variable "psql_major" {
  description = "PostgreSQL client major version (16 => installs postgresql-client-16)."
  type        = number
  default     = 16
}

variable "cursor_channel" {
  description = "Cursor channel (best effort). Use 'stable'."
  type        = string
  default     = "stable"
}

variable "ssh_key_dir" {
  description = "Directory to save SSH private key (use absolute path or ~ will be expanded using home_dir). Defaults to ~/.ssh/auto_clouds"
  type        = string
  default     = "~/.ssh/auto_clouds"
}

variable "home_dir" {
  description = "Home directory path (used to expand ~ in ssh_key_dir). Defaults to $HOME environment variable"
  type        = string
  default     = ""
}
