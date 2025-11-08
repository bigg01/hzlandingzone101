# Data source for reading SSH public key content
data "local_file" "ssh_public_key" {
  filename = var.ssh_public_key_path
}
