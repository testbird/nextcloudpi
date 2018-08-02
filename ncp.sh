#!/bin/bash

# NextCloudPi additions to Raspbian 
#
# Copyleft 2017 by Ignacio Nunez Hernanz <nacho _a_t_ ownyourbits _d_o_t_ com>
# GPL licensed (see end of file) * Use at your own risk!
#
# More at https://nextcloudpi.com
#

WEBADMIN=ncp
WEBPASSWD=ownyourbits
BRANCH=master

CONFDIR=/usr/local/etc/ncp-config.d/
APTINSTALL="apt-get install -y --no-install-recommends"
export DEBIAN_FRONTEND=noninteractive


install()
{
  # NCP-CONFIG
  apt-get update
  $APTINSTALL dialog whiptail
  mkdir -p $CONFDIR

  # include option in raspi-config (only Raspbian)
  test -f /usr/bin/raspi-config && {
    sed -i '/Change User Password/i"0 NextCloudPi Configuration" "Configuration of NextCloudPi" \\' /usr/bin/raspi-config
    sed -i '/1\\ \*) do_change_pass ;;/i0\\ *) ncp-config ;;'                                       /usr/bin/raspi-config
  }

  # add the ncc shortcut
  cat > /usr/local/bin/ncc <<'EOF'
#!/bin/bash
sudo -u www-data php /var/www/nextcloud/occ "$@"
EOF
  chmod +x /usr/local/bin/ncc

  # NCP-WEB

  ## VIRTUAL HOST
  cat > /etc/apache2/sites-available/ncp-activation.conf <<EOF
<VirtualHost _default_:443>
  DocumentRoot /var/www/ncp-web/
  SSLEngine on
  SSLCertificateFile      /etc/ssl/certs/ssl-cert-snakeoil.pem
  SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key

</VirtualHost>
<Directory /var/www/ncp-web/>
  <RequireAll>

   <RequireAny>
      Require host localhost
      Require local
      Require ip 192.168
      Require ip 172
      Require ip 10
   </RequireAny>

  </RequireAll>
</Directory>
EOF

  cat > /etc/apache2/sites-available/ncp.conf <<EOF
Listen 4443
<VirtualHost _default_:4443>
  DocumentRoot /var/www/ncp-web
  SSLEngine on
  SSLCertificateFile      /etc/ssl/certs/ssl-cert-snakeoil.pem
  SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key

  # 2 days to avoid very big backups requests to timeout
  TimeOut 172800

  <IfModule mod_authnz_external.c>
    DefineExternalAuth pwauth pipe /usr/sbin/pwauth
  </IfModule>

</VirtualHost>
<Directory /var/www/ncp-web/>

  AuthType Basic
  AuthName "ncp-web login"
  AuthBasicProvider external
  AuthExternal pwauth

  SetEnvIf Request_URI "^" noauth
  SetEnvIf Request_URI "^index\.php$" !noauth
  SetEnvIf Request_URI "^/$" !noauth
  SetEnvIf Request_URI "^/wizard/index.php$" !noauth
  SetEnvIf Request_URI "^/wizard/$" !noauth

  <RequireAll>

   <RequireAny>
      Require host localhost
      Require local
      Require ip 192.168
      Require ip 172
      Require ip 10
   </RequireAny>

   <RequireAny>
      Require env noauth
      Require user $WEBADMIN
   </RequireAny>

  </RequireAll>

</Directory>
EOF

  $APTINSTALL libapache2-mod-authnz-external pwauth
  a2enmod authnz_external authn_core auth_basic
  a2dissite nextcloud
  a2ensite ncp-activation

  ## NCP USER FOR AUTHENTICATION
  if id ncp >/dev/null 2>&1
  echo -e "$WEBPASSWD\n$WEBPASSWD" | passwd "$WEBADMIN"
  then
  chsh -s /usr/sbin/nologin "$WEBADMIN"
    echo "WARNING: user \"ncp\" already existed!" 
  else
    useradd --home-dir /nonexistent "$WEBADMIN"
    echo -e "$WEBPASSWD\n$WEBPASSWD" | passwd "$WEBADMIN"
    chsh -s /usr/sbin/nologin "$WEBADMIN"
  fi
  
  ## NCP LAUNCHER
  mkdir -p /home/www
  chown www-data:www-data /home/www
  chmod 700 /home/www

  cat > /home/www/ncp-launcher.sh <<'EOF'
#!/bin/bash
DIR=/usr/local/etc/ncp-config.d
test -f $DIR/$1 || { echo "File not found"; exit 1; }
source /usr/local/etc/library.sh
cd $DIR
launch_script $1
EOF
  chmod 700 /home/www/ncp-launcher.sh
  echo "www-data ALL = NOPASSWD: /home/www/ncp-launcher.sh , /sbin/halt, /sbin/reboot" >> /etc/sudoers

  # NCP AUTO TRUSTED DOMAIN
  mkdir -p /usr/lib/systemd/system
  cat > /usr/lib/systemd/system/nextcloud-domain.service <<'EOF'
[Unit]
Description=Register Current IP as Nextcloud trusted domain
Requires=network.target
After=mysql.service

[Service]
ExecStart=/bin/bash /usr/local/bin/nextcloud-domain.sh
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

  cat > /usr/local/bin/nextcloud-domain.sh <<'EOF'
#!/bin/bash
# wicd service finishes before completing DHCP
while :; do
  IFACE="$( ip r | grep "default via" | awk '{ print $5 }' | head -1 )"
  IP="$( ip a show dev "$IFACE" | grep global | grep -oP '\d{1,3}(.\d{1,3}){3}' | head -1 )"
  [[ "$IP" != "" ]] && break
  sleep 3
done
cd /var/www/nextcloud
sudo -u www-data php occ config:system:set trusted_domains 1 --value=$IP
EOF

  # make sure this is called on last re-boot
  [[ "$DOCKERBUILD" != 1 ]] && systemctl enable nextcloud-domain 

  # NEXTCLOUDPI UPDATES
  cat > /etc/cron.daily/ncp-check-version <<EOF
#!/bin/sh
/usr/local/bin/ncp-check-version
EOF
  chmod a+x /etc/cron.daily/ncp-check-version
  touch               /var/run/.ncp-latest-version
  chown root:www-data /var/run/.ncp-latest-version
  chmod g+w           /var/run/.ncp-latest-version

  # update to latest version from github as part of the build process
  $APTINSTALL git
  wget https://raw.githubusercontent.com/nextcloud/nextcloudpi/$BRANCH/bin/ncp-update -O /usr/local/bin/ncp-update
  chmod a+x /usr/local/bin/ncp-update

  /usr/local/bin/ncp-update $BRANCH

  # ONLY FOR IMAGE BUILDS
  if [[ -f /.ncp-image ]]; then
    rm -rf /var/log/ncp.log

    ## NEXTCLOUDPI MOTD 
    rm -rf /etc/update-motd.d
    mkdir /etc/update-motd.d
    rm /etc/motd
    ln -s /var/run/motd /etc/motd

    cat > /etc/update-motd.d/10logo <<EOF
#!/bin/sh
echo
cat /usr/local/etc/ncp-ascii.txt
EOF

    cat > /etc/update-motd.d/20updates <<'EOF'
#!/bin/bash
/usr/local/bin/ncp-check-updates
EOF
    chmod a+x /etc/update-motd.d/*

    ## HOSTNAME AND mDNS
    $APTINSTALL avahi-daemon
    echo nextcloudpi > /etc/hostname
    sed -i '$c127.0.1.1 nextcloudpi' /etc/hosts

    ## tag image
    echo "NextCloudPi_$( date  "+%m-%d-%y" )" > /usr/local/etc/ncp-baseimage

    ## SSH hardening
    if [[ -f /etc/ssh/sshd_config ]]; then
      sed -i 's|^#AllowTcpForwarding .*|AllowTcpForwarding no|'     /etc/ssh/sshd_config
      sed -i 's|^#ClientAliveCountMax .*|ClientAliveCountMax 2|'    /etc/ssh/sshd_config
      sed -i 's|^MaxAuthTries .*|MaxAuthTries 1|'                   /etc/ssh/sshd_config
      sed -i 's|^#MaxSessions .*|MaxSessions 2|'                    /etc/ssh/sshd_config
      sed -i 's|^#TCPKeepAlive .*|TCPKeepAlive no|'                 /etc/ssh/sshd_config
      sed -i 's|^X11Forwarding .*|X11Forwarding no|'                /etc/ssh/sshd_config
      sed -i 's|^#LogLevel .*|LogLevel VERBOSE|'                    /etc/ssh/sshd_config
      sed -i 's|^#Compression .*|Compression no|'                   /etc/ssh/sshd_config
      sed -i 's|^#AllowAgentForwarding .*|AllowAgentForwarding no|' /etc/ssh/sshd_config
    fi

    ## kernel hardening
    cat >> /etc/sysctl.conf <<EOF
fs.protected_hardlinks=1
fs.protected_symlinks=1
kernel.core_uses_pid=1
kernel.dmesg_restrict=1
kernel.kptr_restrict=2
kernel.sysrq=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.log_martians=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.default.accept_source_route=0
net.ipv4.conf.default.log_martians=1
net.ipv4.tcp_timestamps=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
EOF

    ## other tweaks
    sed -i "s|^UMASK.*|UMASK           027|" /etc/login.defs
  fi
}

configure() { :; }


# License
#
# This script is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This script is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this script; if not, write to the
# Free Software Foundation, Inc., 59 Temple Place, Suite 330,
# Boston, MA  02111-1307  USA
