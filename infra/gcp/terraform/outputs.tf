output "public_ip" {
  value = google_compute_instance.this.network_interface[0].access_config[0].nat_ip
}
output "rdp_host" {
  value = "${google_compute_instance.this.network_interface[0].access_config[0].nat_ip}:3389"
}
output "ssh_command" {
  value = "gcloud compute ssh ${google_compute_instance.this.name} --zone=${var.zone}"
}
