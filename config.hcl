ui = true

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

storage "postgresql" {
  connection_url = "postgresql://postgres:postgres@postgres:5432/vaultdb?sslmode=disable"
}

api_addr = "http://127.0.0.1:8200"

disable_mlock = "true"
