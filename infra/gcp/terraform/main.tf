provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2404-lts-amd64"
  project = "ubuntu-os-cloud"
}

resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = true
}

resource "google_compute_firewall" "allow_ssh_rdp" {
  name    = "${var.name_prefix}-allow-ssh-rdp"
  network = google_compute_network.vpc.name

  allow { protocol = "tcp" ports = ["22", "3389"] }

  source_ranges = [var.allowed_cidr]
  target_tags   = ["${var.name_prefix}-vm"]
}

locals {
  startup_script = templatefile("${path.module}/startup.sh.tftpl", {
    dev_username          = var.dev_username
    rdp_password          = var.rdp_password
    git_version           = var.git_version
    python_version        = var.python_version
    node_version          = var.node_version
    npm_version           = var.npm_version
    docker_version_prefix = var.docker_version_prefix
    awscli_version        = var.awscli_version
    psql_major            = var.psql_major
    cursor_channel        = var.cursor_channel
  })
}

resource "google_compute_instance" "this" {
  name         = "${var.name_prefix}-vm"
  machine_type = var.machine_type
  tags         = ["${var.name_prefix}-vm"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = var.boot_disk_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    network = google_compute_network.vpc.name
    access_config {}
  }

  metadata = {
    startup-script = local.startup_script
  }

  scheduling {
    provisioning_model = var.use_spot ? "SPOT" : "STANDARD"
    preemptible        = var.use_spot
    automatic_restart  = var.use_spot ? false : true
  }

  service_account { scopes = ["cloud-platform"] }
}
