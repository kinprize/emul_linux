#!/bin/sh

# Script for automated installation of VHCI drivers with HASP drivers
# It's intended for use on CentOS 7/8 machines.

# Getting OS version
OSv=`cat /etc/centos-release | sed -E 's/[^0-9]+([0-9]).*/\1/'`
if [ ${OSv} -eq 7 ]; then
    echo "CentOS 7 detected. Using yum."
    YUM="/usr/bin/yum"
else
    if [ ${OSv} -eq 8 ]; then
        echo "CentOS 8 detected. Using dnf."
        YUM="/usr/bin/dnf"
        # TAR not installed in Core release
        echo "Installing TAR"
        ORINSTALLED=`dnf list installed | grep -c ^tar`
        if [ ${ORINSTALLED} -eq 0 ]; then
            ${YUM} install -q -y tar.x86_64
        fi
    else
        echo "Unsupported OS detected. Script tested only on CentOS 7/8"
        exit 1
    fi
fi

# Getting kernel version
KVER=`uname -r`

# Installing development packages
echo "Installing build tools"
${YUM} install -q -y gcc.x86_64 gcc-c++.x86_64 make.x86_64
echo "Installing kernel headers"
${YUM} install -q -y kernel-devel.x86_64
echo "Installing build dependencies"
${YUM} install -q -y jansson-devel.x86_64 libusb.i686 elfutils-libelf-devel.x86_64    git.x86_64
echo "Installing GIT"
${YUM} install -q -y git.x86_64
echo ""

cd /root
echo "Downloading and installing HASP driver / license manager"
curl -Os http://download.etersoft.ru/pub/Etersoft/HASP/last/CentOS/7/haspd-7.90-eter2centos.x86_64.rpm
yum localinstall -q -y haspd-7.90-eter2centos.x86_64.rpm >/dev/null 2>&1
systemctl -q enable haspd
echo ""

# Downloading sources
cd /usr/src
echo "Downloading VHCI_HCD sources"
curl -sL https://sourceforge.net/projects/usb-vhci/files/linux%20kernel%20module/vhci-hcd-1.15.tar.gz/download > vhci-hcd-1.15.tar.gz
echo "Downloading LIBUSB_VHCI sources"
curl -sL https://sourceforge.net/projects/usb-vhci/files/native%20libraries/libusb_vhci-0.8.tar.gz/download > libusb_vhci-0.8.tar.gz
echo "Downloading USB_HASP sources"
git clone https://github.com/sam88651/UsbHasp.git >/dev/null 2>&1
if [ -f libusb_vhci-0.8.tar.gz ]; then
    echo "Extracting VHCI_HCD"
    tar -xpf libusb_vhci-0.8.tar.gz
else
    echo "File libusb_vhci-0.8.tar.gz has not been downloaded. Exiting"
    exit 1
fi
if [ -f vhci-hcd-1.15.tar.gz ]; then
    echo "Extracting LIBUSB_VHCI"
    tar -xpf vhci-hcd-1.15.tar.gz
else
    echo "File vhci-hcd-1.15.tar.gz has not been downloaded. Exiting"
    exit 1
fi
echo ""

echo "Compiling VHCI_HCD"
cd vhci-hcd-1.15
mkdir -p linux/${KVER}/drivers/usb/core
cp /usr/src/kernels/${KVER}/include/linux/usb/hcd.h linux/${KVER}/drivers/usb/core
sed -i 's/\#define DEBUG/\/\/#define DEBUG/' usb-vhci-hcd.c
sed -i 's/\#define DEBUG/\/\/#define DEBUG/' usb-vhci-iocifc.c
make KVERSION=${KVER} >/dev/null 2>&1
echo "Installing VHCI_HCD"
make install >/dev/null 2>&1
echo "usb_vhci_hcd" >> /etc/modules-load.d/usb_vhci.conf
echo "Trying to load module usb_vhci_hcd"
modprobe usb_vhci_hcd
echo "usb_vhci_iocifc" >> /etc/modules-load.d/usb_vhci.conf
echo "Trying to load module usb_vhci_iocifc"
modprobe usb_vhci_iocifc
cd ..
echo ""

echo "Compiling LIBUSB_VHCI"
cd libusb_vhci-0.8
./configure >/dev/null 2>&1
make -s >/dev/null 2>&1
echo "Installing LIBUSB_VHCI"
make install >/dev/null 2>&1
echo "/usr/local/lib" >> /etc/ld.so.conf.d/libusb_vhci.conf
ldconfig
cd ..
echo ""

echo "Compiling UsbHasp"
cd UsbHasp
# Compiler throws errors on CentOS 7 complaining about C standards
if [ ${OSv} -eq 7 ]; then
    sed -i 's/\(CC=gcc\)/\1 -std=gnu11/' nbproject/Makefile-Release.mk
fi
make -s >/dev/null 2>&1
echo "Installing UsbHasp"
cp dist/Release/GNU-Linux/usbhasp /usr/local/sbin
# Directory for keys
mkdir /etc/usbhaspkey/
# SystemD unit for loading keys on boot
cat <<EOF >> /etc/systemd/system/usbhaspemul.service
[Unit]
Description=Emulation HASP key for 1C
Requires=haspd.service
After=haspd.service

[Service]
Type=simple
ExecStart=/usr/bin/sh -c 'find /etc/usbhaspkey -name "*.json" | xargs /usr/local/sbin/usbhasp'
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload SystemD configuration
systemctl daemon-reload 
systemctl -q enable usbhaspemul
echo "Trying to start USB HASP Emulator"
systemctl start usbhaspemul

# Open UDP port 475 for incoming connections
echo "Setting up firewall"
firewall-cmd --quiet --permanent --new-service=hasplm
firewall-cmd --quiet --permanent --service=hasplm --add-port=475/udp
firewall-cmd --quiet --permanent --add-service=hasplm
firewall-cmd --quiet --reload
echo ""

echo "Installation finished. Place any keys in .json format into directory /etc/usbhaspkey"
echo "After that you can restart usbhaspemul service and configuration will be finished."

