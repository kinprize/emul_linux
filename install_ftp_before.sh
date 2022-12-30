#Update & Upgrade
echo "Update system"
yum -q -y update
yum -q -y upgrade

# Installing development packages
echo "Install Advanced packages"
yum install -q -y deltarpm 
yum install -q -y epel-release 
yum install -q -y gcc.x86_64 gcc-c++.x86_64 make.x86_64
yum install -q -y kernel-devel.x86_64
yum install -q -y jansson-devel.x86_64 libusb.i686 elfutils-libelf-devel.x86_64    git.x86_64
yum install -q -y git.x86_64
echo ""

reboot