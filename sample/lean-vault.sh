#!/bin/bash
# shellcheck disable=SC2005,SC2030,SC2031,SC2174
#
# This script helps manage Vault running in a multi-node cluster
# using the integrated storage (Raft) backend.

set -e

home_dir="$(pwd)"
script_name="$(basename "$0")"
os_name="$(uname -s | awk '{print tolower($0)}')"

if [ "$os_name" != "darwin" ] && [ "$os_name" != "linux" ]; then
  >&2 echo "Sorry, this script supports only Linux or macOS operating systems."
  exit 1
fi

# Node IPs
node_0_ip="172.31.56.196"
node_1_ip="172.31.51.64"
node_2_ip="172.31.54.29"
node_3_ip="172.31.63.186"


function vault_to_network_address {
  local vault_node_name=$1

  case "$vault_node_name" in
    vault_0)
      echo "http://$node_0_ip:8200"
      ;;
    vault_1)
      echo "http://$node_1_ip:8200"
      ;;
    vault_2)
      echo "http://$node_2_ip:8200"
      ;;
    vault_3)
      echo "http://$node_3_ip:8200"
      ;;
  esac
}

# Create a helper function to address the first vault node
function vault_0 {
    (export VAULT_ADDR=http://$node_0_ip:8200 && vault "$@")
}

# Create a helper function to address the second vault node
function vault_1 {
    (export VAULT_ADDR=http://$node_1_ip:8200 && vault "$@")
}

# Create a helper function to address the third vault node
function vault_2 {
    (export VAULT_ADDR=http://$node_2_ip:8200 && vault "$@")
}

# Create a helper function to address the fourth vault node
function vault_3 {
    (export VAULT_ADDR=http://$node_3_ip:8200 && vault "$@")
}

function stop_vault {
  local vault_node_name=$1

  service_count=$(pgrep -f "$(pwd)"/config-"$vault_node_name" | wc -l | tr -d '[:space:]')

  printf "\n%s" \
    "Found $service_count Vault service(s) matching that name"

  if [ "$service_count" != "0" ] ; then
    printf "\n%s" \
      "[$vault_node_name] stopping" \
      ""

    pkill -f "$(pwd)/config-$vault_node_name"
  fi
}

function stop {
  case "$1" in
    vault_0)
      stop_vault "vault_0"
      ;;
    vault_1)
      stop_vault "vault_1"
      ;;
    vault_2)
      stop_vault "vault_2"
      ;;
    vault_3)
      stop_vault "vault_3"
      ;;
    all)
      for vault_node_name in vault_0 vault_1 vault_2 vault_3 ; do
        stop_vault $vault_node_name
      done
      ;;
    *)
      printf "\n%s" \
        "Usage: $script_name stop [all|vault_0|vault_1|vault_2|vault_3]" \
        ""
      ;;
    esac
}

function start_vault {
  local vault_node_name=$1

  local vault_network_address
  vault_network_address=$(vault_to_network_address "$vault_node_name")
  local vault_config_file=$home_dir/config-$vault_node_name.hcl
  local vault_log_file=$home_dir/$vault_node_name.log

  printf "\n%s" \
    "[$vault_node_name] starting Vault server @ $vault_network_address" \
    ""

  # vault_0 when started should not be looking for a token. It should be
  # creating the token.

  if [[ "$vault_node_name" != "vault_0" ]] ; then
    if [[ -e "$home_dir/root_token-vault_0" ]] ; then
      VAULT_TOKEN=$(cat "$home_dir"/root_token-vault_0)

      printf "\n%s" \
        "Using [vault_0] root token ($VAULT_TOKEN) to retrieve transit key for auto-unseal"
      printf "\n"
    fi
  fi

  VAULT_TOKEN=$VAULT_TOKEN VAULT_API_ADDR=$vault_network_address vault server -log-level=trace -config "$vault_config_file" > "$vault_log_file" 2>&1 &
}

function start {
  case "$1" in
    vault_0)
      start_vault "vault_0"
      ;;
    vault_1)
      start_vault "vault_1"
      ;;
    vault_2)
      start_vault "vault_2"
      ;;
    vault_3)
      start_vault "vault_3"
      ;;
    all)
      for vault_node_name in vault_0 vault_1 vault_2 vault_3 ; do
        start_vault $vault_node_name
      done
      ;;
    *)
      printf "\n%s" \
        "Usage: $script_name stop [all|vault_0|vault_1|vault_2|vault_3]" \
        ""
      ;;
    esac
}


function status {
  service_count=$(pgrep -f "$(pwd)"/config | wc -l | tr -d '[:space:]')

  printf "\n%s" \
    "Found $service_count Vault services" \
    ""

  if [[ "$service_count" != 4 ]] ; then
    printf "\n%s" \
    "Unable to find all Vault services" \
    ""
  fi

  printf "\n%s" \
    "[vault_0] status" \
    ""
  vault_0 status || true

  printf "\n%s" \
    "[vault_1] status" \
    ""
  vault_1 status || true

  printf "\n%s" \
    "[vault_2] status" \
    ""
  vault_2 status || true

  printf "\n%s" \
    "[vault_3] status" \
    ""
  vault_3 status || true

  sleep 2
}



function create_config_vault_0 {

  printf "\n%s" \
    "[vault_0] Creating configuration" \
    "  - creating $home_dir/config-vault_0.hcl"

  rm -f config-vault_0.hcl

  tee "$home_dir"/config-vault_0.hcl 1> /dev/null <<EOF
storage "inmem" {}

listener "tcp" {
   address = "$node_0_ip:8200"
   tls_disable = true
}

ui = true
disable_mlock = true
EOF

  printf "\n"
}


function create_config_vault_1 {

  printf "\n%s" \
    "[vault_1] Creating configuration" \
    "  - creating $home_dir/config-vault_1.hcl" \
    "  - creating $home_dir/raft-vault_1"

  rm -f config-vault_1.hcl
  rm -rf "$home_dir"/raft-vault_1
  mkdir -pm 0755 "$home_dir"/raft-vault_1

  tee "$home_dir"/config-vault_1.hcl 1> /dev/null <<EOF
storage "raft" {
   path    = "$home_dir/raft-vault_1/"
   node_id = "vault_1"
   retry_join {
      leader_api_addr = "http://$node_1_ip:8200"
   }
   retry_join {
      leader_api_addr = "http://$node_2_ip:8200"
   }
   retry_join {
      leader_api_addr = "http://$node_3_ip:8200"
   }
}

listener "tcp" {
   address = "$node_1_ip:8200"
   cluster_address = "$node_1_ip:8201"
   tls_disable = true
}

seal "transit" {
   address            = "http://$node_0_ip:8200"
   # token is read from VAULT_TOKEN env
   # token              = ""
   disable_renewal    = "false"

   // Key configuration
   key_name           = "unseal_key"
   mount_path         = "transit/"
}

ui = true
disable_mlock = true
cluster_addr = "http://$node_1_ip:8201"
EOF

  printf "\n"
}



function create_config_vault_2 {

  printf "\n%s" \
    "[vault_2] Creating configuration" \
    "  - creating $home_dir/config-vault_2.hcl" \
    "  - creating $home_dir/raft-vault_2"

  rm -f config-vault_2.hcl
  rm -rf "$home_dir"/raft-vault_2
  mkdir -pm 0755 "$home_dir"/raft-vault_2

  tee "$home_dir"/config-vault_2.hcl 1> /dev/null <<EOF
storage "raft" {
   path    = "$home_dir/raft-vault_2/"
   node_id = "vault_2"
   retry_join {
      leader_api_addr = "http://$node_1_ip:8200"
   }
   retry_join {
      leader_api_addr = "http://$node_2_ip:8200"
   }
   retry_join {
      leader_api_addr = "http://$node_3_ip:8200"
   }
}

listener "tcp" {
   address = "$node_2_ip:8200"
   cluster_address = "$node_2_ip:8201"
   tls_disable = true
}

seal "transit" {
   address            = "http://$node_0_ip:8200"
   # token is read from VAULT_TOKEN env
   # token              = ""
   disable_renewal    = "false"

   // Key configuration
   key_name           = "unseal_key"
   mount_path         = "transit/"
}

ui = true
disable_mlock = true
cluster_addr = "http://$node_2_ip:8201"
EOF

  printf "\n"
}



function create_config_vault_3 {

  printf "\n%s" \
    "[vault_3] Creating configuration" \
    "  - creating $home_dir/config-vault_3.hcl" \
    "  - creating $home_dir/raft-vault_3"

  rm -f config-vault_3.hcl
  rm -rf "$home_dir"/raft-vault_3
  mkdir -pm 0755 "$home_dir"/raft-vault_3

  tee "$home_dir"/config-vault_3.hcl 1> /dev/null <<EOF
storage "raft" {
   path    = "$home_dir/raft-vault_3/"
   node_id = "vault_3"
   retry_join {
      leader_api_addr = "http://$node_1_ip:8200"
   }
   retry_join {
      leader_api_addr = "http://$node_2_ip:8200"
   }
   retry_join {
      leader_api_addr = "http://$node_3_ip:8200"
   }
}

listener "tcp" {
   address = "$node_3_ip:8200"
   cluster_address = "$node_3_ip:8201"
   tls_disable = true
}

seal "transit" {
   address            = "http://$node_0_ip:8200"
   # token is read from VAULT_TOKEN env
   # token              = ""
   disable_renewal    = "false"

   // Key configuration
   key_name           = "unseal_key"
   mount_path         = "transit/"
}

ui = true
disable_mlock = true
cluster_addr = "http://$node_3_ip:8201"
EOF
  printf "\n"
}

function setup_vault_0 {
  
  create_config_vault_0

  start_vault "vault_0"
  sleep 5

  printf "\n%s" \
    "[vault_0] initializing and capturing the unseal key and root token" \
    ""
  sleep 2 # Added for human readability

  INIT_RESPONSE=$(vault_0 operator init -format=json -key-shares 1 -key-threshold 1)

  UNSEAL_KEY=$(echo "$INIT_RESPONSE" | jq -r .unseal_keys_b64[0])
  VAULT_TOKEN=$(echo "$INIT_RESPONSE" | jq -r .root_token)

  echo "$UNSEAL_KEY" > unseal_key-vault_0
  echo "$VAULT_TOKEN" > root_token-vault_0

  printf "\n%s" \
    "[vault_0] Unseal key: $UNSEAL_KEY" \
    "[vault_0] Root token: $VAULT_TOKEN" \
    ""

  printf "\n%s" \
    "[vault_0] unsealing and logging in" \
    ""
  sleep 2 # Added for human readability

  vault_0 operator unseal "$UNSEAL_KEY"
  vault_0 login "$VAULT_TOKEN"

  printf "\n%s" \
    "[vault_0] enabling the transit secret engine and creating a key to auto-unseal vault cluster" \
    ""
  sleep 5 # Added for human readability

  vault_0 secrets enable transit
  vault_0 write -f transit/keys/unseal_key
}

function setup_vault_1 {
  create_config_vault_1

  start_vault "vault_1"
  sleep 5

  printf "\n%s" \
    "[vault_1] initializing and capturing the recovery key and root token" \
    ""
  sleep 2 # Added for human readability

  # Initialize the second node and capture its recovery keys and root token
  INIT_RESPONSE2=$(vault_1 operator init -format=json -recovery-shares 1 -recovery-threshold 1)

  RECOVERY_KEY2=$(echo "$INIT_RESPONSE2" | jq -r .recovery_keys_b64[0])
  VAULT_TOKEN2=$(echo "$INIT_RESPONSE2" | jq -r .root_token)

  echo "$RECOVERY_KEY2" > recovery_key-vault_1
  echo "$VAULT_TOKEN2" > root_token-vault_1

  printf "\n%s" \
    "[vault_1] Recovery key: $RECOVERY_KEY2" \
    "[vault_1] Root token: $VAULT_TOKEN2" \
    ""

  printf "\n%s" \
    "[vault_1] waiting to finish post-unseal setup (15 seconds)" \
    ""

  sleep 15

  printf "\n%s" \
    "[vault_1] logging in and enabling the KV secrets engine" \
    ""
  sleep 2 # Added for human readability

  vault_1 login "$VAULT_TOKEN2"
  vault_1 secrets enable -path=kv kv-v2
  sleep 2

  printf "\n%s" \
    "[vault_1] storing secret 'kv/apikey' to demonstrate snapshot and recovery methods" \
    ""
  sleep 2 # Added for human readability

  #test
  vault_1 kv put kv/apikey webapp=ABB39KKPTWOR832JGNLS02
  vault_1 kv get kv/apikey

  export VAULT_ADDR="http://$node_1_ip:8200"

}

function setup_vault_2 {
  create_config_vault_2

  start_vault "vault_2"
  sleep 2
  export VAULT_ADDR="http://$node_2_ip:8200"
}

function setup_vault_3 {
  create_config_vault_3
  start_vault "vault_3"
  sleep 2
  export VAULT_ADDR="http://$node_3_ip:8200"
}

function create {
  case "$1" in
    network)
      shift ;
      create_network "$@"
      ;;
    config)
      shift ;
      create_config "$@"
      ;;
    *)
      printf "\n%s" \
      "Creates resources for the cluster." \
      "Usage: $script_name create [network|config]" \
      ""
      ;;
  esac
}

function setup {
  case "$1" in
    vault_0)
      setup_vault_0
      ;;
    vault_1)
      setup_vault_1
      ;;
    vault_2)
      setup_vault_2
      ;;
    vault_3)
      setup_vault_3
      ;;
    all)
      for vault_setup_function in setup_vault_0 setup_vault_1 setup_vault_2 setup_vault_3 ; do
        $vault_setup_function
      done
      ;;
    *)
      printf "\n%s" \
      "Sets up resources for the cluster" \
      "Usage: $script_name setup [all|vault_0|vault_1|vault_2|vault_3]" \
      ""
      ;;
  esac
}

case "$1" in
  create)
    shift ;
    create "$@"
    ;;
  setup)
    shift ;
    setup "$@"
    ;;
  vault_0)
    shift ;
    vault_0 "$@"
    ;;
  vault_1)
    shift ;
    vault_1 "$@"
    ;;
  vault_2)
    shift ;
    vault_2 "$@"
    ;;
  vault_3)
    shift ;
    vault_3 "$@"
    ;;
  status)
    status
    ;;
  start)
    shift ;
    start "$@"
    ;;
  stop)
    shift ;
    stop "$@"
    ;;
  clean)
    stop all
    clean
    ;;
  *)
    printf "\n%s" \
      "This script helps manages a Vault HA cluster with raft storage." \
      "" \
      "Usage: $script_name [create|setup|status|stop|clean|vault_0|vault_1|vault_2|vault_3]" \
      ""
    ;;
esac

