# Variable for your public key's path
variable "public_key_path" {
  description = "C:/Users/rajav/.ssh/srm-server-key.pub" # Path to your SSH public key file.
  # --- IMPORTANT ---
  # Update this default path to match your username
  default = "C:/Users/rajav/.ssh/srm-server-key.pub"
}
