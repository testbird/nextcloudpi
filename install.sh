#!/bin/bash

# NextCloudPi installation script
#
# Copyleft 2017 by Ignacio Nunez Hernanz <nacho _a_t_ ownyourbits _d_o_t_ com>
# GPL licensed (see end of file) * Use at your own risk!
#
# Usage: ./install.sh 
#
# more details at https://ownyourbits.com

BRANCH=master

if [ apt-get -s install php7.2 ]
then
  PHPVER=7.2
else
  PHPVER=7.0
fi


#DBG=x
set -e$DBG

TMPDIR="$(mktemp -d /tmp/nextcloudpi.XXXXXX || (echo "Failed to create temp dir. Exiting" >&2 ; exit 1) )"
trap "rm -rf \"${TMPDIR}\" ; exit 0" 0 1 2 3 15

[[ ${EUID} -ne 0 ]] && {
  printf "Must be run as root. Try 'sudo $0'\n"
  exit 1
}

# check_distro 
grep -q -e "Debian GNU/Linux" -e "Raspbian GNU/Linux" /etc/issue || {
  echo "distro not supported"; 
  exit 1; 
}


# get install code
echo "Getting build code..."
apt-get update
apt-get install --no-install-recommends -y wget ca-certificates sudo

pushd "$TMPDIR"

# TODO before merging: set this back to orig. nextcloud/nextcloudpi
wget -O- --content-disposition https://github.com/testbird/nextcloudpi/archive/"$BRANCH"/latest.tar.gz \
  | tar -xz \
  || exit 1
cd - && cd "$TMPDIR"/nextcloudpi-"$BRANCH"


# install NCP
echo -e "\nInstalling NextCloudPi"
source etc/library.sh

install_script  lamp.sh

install_script  etc/ncp-config.d/nc-nextcloud.sh
activate_script etc/ncp-config.d/nc-nextcloud.sh

install_script  ncp.sh

activate_script etc/ncp-config.d/nc-init.sh

[[ -f /.ncp-image ]] && install_script post-inst.sh

popd
echo "Done.

Type 'sudo ncp-config' to configure NCP, or access ncp-web on https://<this_ip>:4443
"

exit 0

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
