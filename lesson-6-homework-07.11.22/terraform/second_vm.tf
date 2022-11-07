resource "yandex_compute_disk" "test-pg1-liverace-boot-disk" {
  name     = "test-pg1-liverace-boot-disk"
  size     = 50
  type     = "network-ssd"
  image_id = "fd83clk0nfo8p172omkn" #debian10
  zone     = var.zone

}


resource "yandex_vpc_address" "static-external-test-pg1-liverace-address" {
  name = "static-external-test-pg1-liverace-address"
  external_ipv4_address {
    zone_id = var.zone
  }
}


resource "yandex_compute_instance" "test-pg1-liverace" {
  name        = "test-pg1-liverace"
  platform_id = "standard-v1"
  zone        = var.zone
  allow_stopping_for_update = true
  resources {
    cores  = 2
    memory = 2
    core_fraction = 0
  }

  boot_disk {
    auto_delete = true
    disk_id = yandex_compute_disk.test-pg1-liverace-boot-disk.id
  }

  network_interface {
    subnet_id = "e9bamfhhg69e99tkm32j"
    nat = true
    nat_ip_address = flatten(yandex_vpc_address.static-external-test-pg1-liverace-address.external_ipv4_address[*].address)[0]
  }

  metadata = {
    ssh-keys = "${var.ssh_username}:${file("~/.ssh/id_rsa.pub.ansible.1")}"
    user-data = data.template_file.user_data.rendered
    }
}
