#Update & Upgrade
echo "Update system"
yum -q -y update
yum -q -y upgrade


KVER=`uname -r`
OSv=`cat /etc/centos-release | sed -E 's/[^0-9]+([0-9]).*/\1/'`
#PC ip and port usb redirect client
CALLBACK='192.168.0.0:32032'

#FTP SETTINGS .json files
FTPUSER='user'
FTPPASS='pass'
FTPHOST='192.168.0.0'
REMOTEDIR="/share/CENTOS1C/DUMPS"
LOCALDIR="/etc/usbhaspkey/"

# Installing development packages
echo "Install Advanced packages"
yum install -q -y mc
yum install -q -y net-tools
yum install -q -y deltarpm 
yum install -q -y epel-release 
yum install -q -y gcc.x86_64 gcc-c++.x86_64 make.x86_64
yum install -q -y kernel-devel.x86_64
yum install -q -y jansson-devel.x86_64 libusb.i686 elfutils-libelf-devel.x86_64    git.x86_64
yum install -q -y git.x86_64
echo ""

# Downloading and installing HASP driver / license manager
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

#FTP
cd $LOCALDIR
ftp -i -n <<EOF
open $FTPHOST
user $FTPUSER $FTPPASS
cd $REMOTEDIR
binary
mget *.json
quit
EOF

#Installing USB redirector
echo "DownloadUSBRedirector"
curl -sL http://www.incentivespro.com/usb-redirector-linux-x86_64.tar.gz > usbredirector.tar.gz
if [ -f usbredirector.tar.gz ]; then
    echo "Extracting usbredirector"
    tar -xpf usbredirector.tar.gz
else
    echo "File usbredirector.tar.gz has not been downloaded. Exiting"
    exit 1
fi
cd usb-redirector-linux-x86_64
echo "USB Redirector installing"
sh ./installer.sh install-server
rm -rf usb-redirector-linux-x86_64
rm -f usbredirector.tar.gz
usbsrv -autoshareon
usbsrv -createcallback $CALLBACK


# SystemD unit for loading keys on boot
cat /dev/null >| /etc/systemd/system/usbhaspemul.service
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

# Open port 475 and 32032 for incoming connections
echo "Setting up firewall"
firewall-cmd --quiet --permanent --new-service=hasplm
firewall-cmd --quiet --permanent --service=hasplm --add-port=475/udp
firewall-cmd --quiet --permanent --service=hasplm --add-port=32032
firewall-cmd --quiet --permanent --add-service=hasplm
firewall-cmd --quiet --reload
echo ""
echo "Installation complite!"

