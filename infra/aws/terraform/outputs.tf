output "public_ip" {
  value = aws_instance.this.public_ip
}

output "public_dns" {
  value = aws_instance.this.public_dns
}

output "rdp_host" {
  value = "${aws_instance.this.public_ip}:3389"
}

output "ssh_command" {
  value = "ssh -i ${local.ssh_key_dir_expanded}/${var.name_prefix}-key.pem ubuntu@${aws_instance.this.public_ip}"
}

output "ssh_key_path" {
  value     = "${local.ssh_key_dir_expanded}/${var.name_prefix}-key.pem"
  sensitive = false
}
