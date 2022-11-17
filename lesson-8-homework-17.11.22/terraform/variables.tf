variable oauth_token {}
variable cloud_id { default = "b1gcbvl7l8bb0p0cns1j" }
variable namespace_id { default = "b1gsfkm1s0ilcju5ufl9" }
variable zone { default = "ru-central1-a" }
variable ssh_username { default = "debian" }

data "template_file" "user_data" {
  template = file("scripts/user.yaml")
}
