
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
      version = "0.79.0"
    }
  }
}

provider "yandex" {
  token                    = var.oauth_token
  cloud_id                 = var.cloud_id
  folder_id                = var.namespace_id
  zone                     = var.zone
}
