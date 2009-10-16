#!/bin/bash

# 64-bit:
#
# apt-get install fakeroot alien pdksh lib32stdc++6 libldap-2.4-2 ldap-utils tftpd gawk ia32-libs xkb-data-legacy


# 32-bit:
#
# apt-get install fakeroot alien sun-java6-jre pdksh  libldap-2.4-2 ldap-utils tftpd libmotif3 gawk

source_dir=$1
if [ -z $source_dir ]; then
    echo "Usage: $0 <srss software source dir>"
    exit 0
fi

here=$(dirname $(readlink -f $0))

tmpdir=/var/tmp/srss.$$
mkdir -p $tmpdir
echo "Using $tmpdir"

for rpm in $source_dir/{Sun_Ray_*,Docs,Kiosk*}/Linux/Packages/*.rpm; do
    rpm2cpio $rpm|(cd $tmpdir; \
        cpio --extract \
             --make-directories \
             --no-absolute-filenames \
             --preserve-modification-time)
done

(
    cd $tmpdir
    wget http://fr.archive.ubuntu.com/ubuntu/pool/main/g/gdbm/libgdbm3_1.8.3-3_i386.deb
    wget http://fr.archive.ubuntu.com/ubuntu/pool/multiverse/o/openmotif/libmotif3_2.2.3-2_i386.deb
    wget http://fr.archive.ubuntu.com/ubuntu/pool/universe/g/glib1.2/libglib1.2ldbl_1.2.10-19build1_i386.deb
)

for extra_pkg in $tmpdir/{libgdbm3_1.8.3-3_i386,libmotif3_2.2.3-2_i386,libglib1.2ldbl_1.2.10-19build1_i386}.deb; do
    echo  "Adding $extra_pkg"
    pkg_tmpdir=/var/tmp/pkg_tmp_dir
    mkdir -p $pkg_tmpdir
    cd $pkg_tmpdir
    fakeroot alien $extra_pkg --to-tgz
    tar xvzf $pkg_tmpdir/*.tgz 
    rm -f $pkg_tmpdir/*.tgz
    cp -R $pkg_tmpdir/usr/* $tmpdir/opt/SUNWut
    if [ -d $pkg_tmpdir/lib ]; then
    	cp -R $pkg_tmpdir/lib/* $tmpdir/opt/SUNWut/lib
    fi
    rm -rf $pkg_tmpdir
done

echo "Adding java..."
mkdir -p $tmpdir/etc/opt/SUNWut
cp $source_dir/Supplemental/Java_Runtime_Environment/Linux/jre-1_5_0_11-linux-i586.bin $tmpdir/usr
cd $tmpdir/usr
(
    function more (){
        true    
    }         
    export -f more
    bash -x ./jre-1_5_0_11-linux-i586.bin < <(printf "yes\n")
)
mv $tmpdir/usr/jre1.5.0_11 $tmpdir/usr/j2se
rm $tmpdir/usr/jre-1_5_0_11-linux-i586.bin
#ln -s /usr/lib/jvm/java-6-sun/jre $tmpdir/etc/opt/SUNWut/jre

echo  "Add zsunray-init script to configure sunray software running from init"
cp $here/zsunray-init $tmpdir/etc/init.d
chmod +x $tmpdir/etc/init.d/zsunray-init

echo "Adding Sun Ray Settings menu utem..."
mkdir -p $tmpdir/usr/share/applications
cat > $tmpdir/usr/share/applications/sunray-settings.desktop << EOF
[Desktop Entry]
Encoding=UTF-8
Name=SunRay Settings
Comment=Adjust audio and video properties
Exec=/opt/SUNWut/bin/utsettings
Icon=gdm-setup.png
Terminal=false
Type=Application
Categories=Application;AudioVideo;
StartupNotify=false
EOF
chmod 644 $tmpdir/usr/share/applications/sunray-settings.desktop

# Setup GDM settings.
echo "Configuring GDM..."
mkdir -p $tmpdir/etc/X11/xdm
mkdir -p $tmpdir/etc/gdm
cat > $tmpdir/etc/gdm/gdm.conf-custom << EOF
[daemon]
PostLoginScriptDir=/etc/X11/gdm/SunRayPostLogin/
PreSessionScriptDir=/etc/X11/gdm/SunRayPreSession/
PostSessionScriptDir=/etc/X11/gdm/SunRayPostSession/
DisplayInitDir=/etc/X11/gdm/SunRayInit
RebootCommand=/bin/false
HaltCommand=/bin/false
SuspendCommand=/bin/false
HibernateCommand=/bin/false
FlexibleXServers=0
VTAllocation=false
DynamicXServers=true
DefaultSession=xfce4.desktop

[xdmcp]
Enable=false

[greeter]
SystemMenu=false
SoundOnLogin=false
ChooserButton=false
Browser=false

[debug]
Enable=true

[servers]
0=inactive

[server-Standard]
name=Standard server
command=/usr/bin/X -br -audit 0
flexible=true

[gui]
AllowGtkThemeChange=false
EOF

cat > $tmpdir/opt/SUNWut/lib/utctl.d/profiles/default <<EO
#
# ident "@(#)default-profile.src        1.6     06/08/23 SMI"
#
# Copyright 2006 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
#
#

#lib64
jre
syslog
cron
#pam
#compatlinks
EO


echo "Patching... SunRay /opt/SUNWut software"
cd $tmpdir/opt/SUNWut
#patch -p3 < $here/srss4.0.debian-3.patch
patch -p3 < $here/sray41-debian.patch.2008-10-30

echo "Patching kernel modules..."
cd $tmpdir/usr/src/SUNWut
#patch -p2 < $here/srss4.0.debian-modules-4.patch
#patch -p1 < $here/modules-4.0-2.diff
#patch -p1 < $here/Patch-modules-SRSS4-0907.txt
#patch -p1 < $here/Patch-modules-SRSS4-0907-phase2.txt
patch -p1 < $here/modules-4.1beta.diff
patch -p1 < $here/tims_patch.diff
cd $tmpdir/usr
for module_dir in src/SUNWut/*; do
    echo "Build module $module_dir..."
    for V in `ls /usr/src|grep 'linux-headers'`; do
        V=$(basename $V|sed s/linux-headers-//g)
        (
            cd $module_dir
            echo $module_dir, $V
            make clean 
            VERSION=$V make
            if [ $? -eq 0 ]; then
                    mkdir -p $tmpdir/lib/modules/$V/misc
                    cp -R *.ko $tmpdir/lib/modules/$V/misc || exit 1
                    make clean
            fi
        )
    done
done

echo "Making empty dirs..."
mkdir -p $tmpdir/var/dt
mkdir -p $tmpdir/var/opt/SUNWut/tokens
mkdir -p $tmpdir/var/opt/SUNWut/displays
mkdir -p $tmpdir/opt/SUNWut/lib/xkb
mkdir -p $tmpdir/opt/SUNWut/lib/xkb/compiled

echo "Fixing xkb stuff..."
(
    cd $tmpdir
    wget http://fr.archive.ubuntu.com/ubuntu/pool/universe/x/xkb-data-legacy/xkb-data-legacy_1.0.1-4_all.deb
    for extra_pkg in $tmpdir/xkb-data-legacy_1.0.1-4_all.deb; do
        pkg_tmpdir=/var/tmp/pkg_tmp_dir
        mkdir -p $pkg_tmpdir
        cd $pkg_tmpdir
        fakeroot alien $extra_pkg --to-tgz
        tar xvzf $pkg_tmpdir/*.tgz 
        rm -f $pkg_tmpdir/*.tgz
        mkdir -p $tmpdir/opt/SUNWut/lib
        cp -R $pkg_tmpdir/usr/share/X11/xkb/* $tmpdir/opt/SUNWut/lib/xkb
        rm -rf $pkg_tmpdir
    done
)
cp -R $tmpdir/opt/SUNWut/lib/xkbfiles/* $tmpdir/opt/SUNWut/lib/xkb
#cd $tmpdir/opt/SUNWut/lib/xkb
#cd geometry ; xkbcomp -lfhlpR -o geometry.dir '*' ; mv geometry.dir ..
#cd ../keycodes ; xkbcomp -lfhlpR -o keycodes.dir '*' ; mv keycodes.dir ..
#cd ../keymap ; xkbcomp -lfhlpR -o keymap.dir '*' ; mv keymap.dir ..
#cd ../symbols ; xkbcomp -lfhlpR -o symbols.dir '*' ; mv symbols.dir ..

echo "Making symlinks..."
mkdir -p $tmpdir/usr/X11R6/lib
ln -s /etc/X11 $tmpdir/usr/X11R6/lib/X11
ln -s /usr/share/X11/XKeysymDB $tmpdir/etc/X11/XKeysymDB
mkdir -p $tmpdir/lib
ln -s /usr/lib32/libldap-2.4.so.2 $tmpdir/opt/SUNWut/lib/libldap.so.199
ln -s /usr/lib32/liblber-2.4.so.2 $tmpdir/opt/SUNWut/lib/liblber.so.199
ln -s /usr/bin/xkbcomp $tmpdir/opt/SUNWut/lib/xkb/xkbcomp
mkdir -p $tmpdir/srv/tftp
ln -s /srv/tftp $tmpdir/tftpboot

echo "Audio setup/fixes..."
mkdir -p $tmpdir/etc/X11/Xsession.d
cat > $tmpdir/etc/X11/Xsession.d/10SUNWut <<EOs
set +e
if [ -x /etc/X11/xinit/xinitrc.d/0010.SUNWut.xdmEnv ]; then
        . /etc/X11/xinit/xinitrc.d/0010.SUNWut.xdmEnv
fi

if [ -x /etc/X11/xinit/xinitrc.d/0100.SUNWut ]; then
#       SUN_SUNRAY_UTXLOCK_PREF=
#       export SUN_SUNRAY_UTXLOCK_PREF
        . /etc/X11/xinit/xinitrc.d/0100.SUNWut
fi

if [ ! -d \$HOME/.pulse ] ; then
        mkdir \$HOME/.pulse
fi

pkill -u \`id -u\` pulseaudio

cat > \$HOME/.pulse/default.pa <<EOcat
load-module module-oss device=\$UTAUDIODEV playback=1 record=1 fragment_size=8192
load-module module-native-protocol-unix
load-module module-esound-protocol-unix
#load-module module-esound-protocol-tcp auth-ip-acl=127.0.0.1
EOcat

# create asoundrc for pulseaudio redirection
cat > \$HOME/.asoundrc <<EOcat
pcm.!default {
  type pulse
}
ctl.!default {
  type pulse
}
EOcat

# start pulseaudio deamon
pulseaudio -D

unset AUDIODEV

set -e
EOs

echo "Setting saving options..."
mkdir -p $tmpdir/etc/X11/gdm/SunRayInit/helpers
cat > $tmpdir/etc/X11/gdm/SunRayInit/helpers/xset <<EOca
#!/bin/bash
xset s 600 0
xset s blank
xset dpms 600 600 600
xset r rate 200 100
xset -b

exit 0
EOca
chmod +x $tmpdir/etc/X11/gdm/SunRayInit/helpers/xset


##echo "Fixing Xnewt..."
##mv $tmpdir/usr/X11R6/bin/Xnewt $tmpdir/usr/X11R6/bin/Xnewt.sun
##cat > $tmpdir/usr/X11R6/bin/Xnewt <<EO
###!/bin/bash
### add -kb as option in case no sane keyboard... +kb if you want the XKEYBOARD
### extention for all Xnewt's. This can be set by the utxconfig program in
### /opt/SUNWut/bin for each session if needed (enable or disable).
###
###  -Tim
##exec /usr/X11R6/bin/Xnewt.sun \$@ -fp /usr/share/fonts/X11/misc
##EO
##chmod +x $tmpdir/usr/X11R6/bin/Xnewt

echo "Making tar..."
cd $tmpdir
fakeroot tar czf $tmpdir/srss-4.1_10.8.tgz *

echo "Making .deb..."
fakeroot alien -d $tmpdir/srss-4.1_10.8.tgz

cp $tmpdir/srss*.deb ~/
rm -rf $tmpdir

