output "static-external-test-pg0-otus-address" {
  value = flatten(yandex_vpc_address.static-external-test-pg0-otus-address.external_ipv4_address[*].address)[0]
}
