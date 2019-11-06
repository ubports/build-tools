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
export BASE_PATH="binaries/"

# Aptly does not need sudo, as the jenkins user is in the aptly group

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
    cd "$WORKSPACE"
    mkdir $BASE_PATH || true
    for suffix in gz bz2 xz deb dsc changes ddeb ; do
      mv *.${suffix} $BASE_PATH || true
    done

    if ! aptly repo show $release ; then
      aptly repo create -distribution="$release" $release
      aptly publish repo $release filesystem:repo:main
    fi
    aptly repo include -no-remove-files -repo="$release" $BASE_PATH
    aptly publish update $release filesystem:repo:main

    # Freight hates ddeb files
    rm $BASE_PATH/*.ddeb || true
		/usr/bin/build-and-provide-package
    for suffix in gz bz2 xz deb dsc changes ; do
      mv $BASE_PATH*.${suffix} $rootwp || true
    done
    cd $rootwp
	done
else
  export release=$(cat branch.buildinfo)
  export distribution=$(cat distribution.buildinfo)
  export REPOS="$release"

  for suffix in gz bz2 xz deb dsc changes ddeb ; do
    mv *.${suffix} $BASE_PATH || true
  done

  if ! aptly repo show $release ; then
    aptly repo create -distribution="$release" $release
    aptly publish repo $release filesystem:repo:main
  fi
  aptly repo include -no-remove-files -repo="$release" $BASE_PATH
  aptly publish update $release filesystem:repo:main

  # Freight hates ddeb files
  rm $BASE_PATH/*.ddeb || true

	/usr/bin/build-and-provide-package
fi
