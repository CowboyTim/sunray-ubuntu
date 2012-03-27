#!/bin/bash

set -e

tmproot=/var/tmp/initrd_netinst.$$
fwsource=http://cdimage.debian.org/cdimage/unofficial/non-free/firmware/squeeze/current/firmware.tar.gz
mkdir -p $tmproot

netinst=http://ftp.debian.org/debian/dists/squeeze/main/installer-amd64/current/images/netboot/netboot.tar.gz

(cd $tmproot
    wget $netinst -O - \
        |tar xvzf - \
            ./debian-installer/amd64/initrd.gz \
            ./debian-installer/amd64/linux
    mv ./debian-installer/amd64/* ./ 

    tmpfw=$tmproot/firmware/
    mkdir -p $tmpfw
    (cd $tmpfw && wget $fwsource -O -|tar xvzf -)
    pax -x sv4cpio -s'%firmware%/firmware%' -w firmware|gzip -c > ./fw.tgz
    cat ./initrd.gz ./fw.tgz > ./initrd_new.gz
)

mv $tmproot/{initrd_new.gz,linux} /tmp/
rm -rf $tmproot/

echo "Written /tmp/linux and /tmp/initrd_new.gz"
