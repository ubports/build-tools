#!/bin/sh

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
export APTLY_ONLY="focal"

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
    for suffix in gz bz2 xz deb dsc changes ddeb udeb buildinfo ; do
      mv *.${suffix} $BASE_PATH || true
    done

    if ! aptly -db-open-attempts=400 repo show $release ; then
      aptly -db-open-attempts=400 repo create -distribution="$release" $release
      aptly -db-open-attempts=400 publish repo $release filesystem:repo:main
    fi
    aptly -db-open-attempts=400 repo include -no-remove-files -repo="$release" $BASE_PATH
    aptly -db-open-attempts=400 publish update $release filesystem:repo:main

    # Freight hates non-standard files
    rm $BASE_PATH/*.ddeb $BASE_PATH/*.udeb || true
		/usr/bin/build-and-provide-package
    for suffix in gz bz2 xz deb dsc change ; do
      mv $BASE_PATH*.${suffix} $rootwp || true
    done
    cd $rootwp
	done
else
  release="$(cat ubports.target_apt_repository.buildinfo)"
  distribution=$(cat distribution.buildinfo)
  REPOS="$release"
  export release distribution REPOS

  for suffix in gz bz2 xz deb dsc changes ddeb udeb buildinfo ; do
    mv *.${suffix} $BASE_PATH || true
  done

  # Publish built packages to Aptly repo.
  if ! aptly -db-open-attempts=400 repo show $release ; then
    aptly -db-open-attempts=400 repo create -distribution="$release" $release
    aptly -db-open-attempts=400 publish repo $release filesystem:repo:main
  fi

  # -no-remove-files leaves the files on the disk, so that we can also publish
  # them to Freight repo.
  aptly -db-open-attempts=400 repo include -no-remove-files -repo="$release" $BASE_PATH
  aptly -db-open-attempts=400 publish update -force-overwrite $release filesystem:repo:main

  if ! echo $APTLY_ONLY | grep -qw $release; then
    # Also publish to Freight repo. Freight is unable to handle .{d,u}deb files,
    # so they have to be removed.
    rm $BASE_PATH/*.ddeb $BASE_PATH/*.udeb || true

    /usr/bin/build-and-provide-package
  fi
fi
