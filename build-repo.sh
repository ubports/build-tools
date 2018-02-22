# Copyright (C) 2017 Marius Gripsgard <marius@ubports.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

set -xe

mkdir -p binaries

export PROVIDE_ONLY=true
export SUDO_CMD=sudo

if [ -f multidist.buildinfo ]; then
	echo "Doing multibuild"
	MULTI_DIST=$(cat multidist.buildinfo)
  for t in multidist*.tar.gz ; do
    tar --overwrite -xvzf $t
  done
	rm multidist*.tar.gz || true
  export rootwp=$(pwd)

	for d in $MULTI_DIST ; do
		echo "Repo-ing for $d"
		export distribution="$d"
    export release="$d"
    export REPOS="$release"
    export WORKSPACE="$rootwp/mbuild/$d"
    export SHIP_FREIGHT_CACHE=true
    cd "$WORKSPACE"
    mkdir binaries/ || true
    for suffix in gz bz2 xz deb dsc changes ; do
      mv *.${suffix} binaries/ || true
    done
    export BASE_PATH="binaries/"
		/usr/bin/build-and-provide-package
    for suffix in gz bz2 xz deb dsc changes ; do
      mv binaries/*.${suffix} $rootwp || true
    done
    cd $rootwp
	done
  sudo freight cache -v -c /etc/freight.conf
else
  export release=$(cat branch.buildinfo)
  export distribution=$(cat distribution.buildinfo)
  export REPOS="$release"
  export BASE_PATH="binaries/"
  for suffix in gz bz2 xz deb dsc changes ; do
    mv *.${suffix} binaries/ || true
  done
	/usr/bin/build-and-provide-package
fi
