sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
sudo dnf upgrade -y
sudo yum install -y wget unzip
sudo yum install -y nano
sudo yum install -y telnet
echo "Installing Vault via HashiCorp Yum repository..."
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install vault
echo "Vault installed successfully."