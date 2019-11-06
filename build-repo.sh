#!/bin/bash

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

# Aptly does not need sudo, as the jenkins user is in the aptly group
# Moving files to a seperate path to make sure we only include what 
# we want in the repos

BASE_PATH="binaries/"

if [ -f multidist.buildinfo ]; then
  echo "Doing multibuild"
  MULTI_DIST=$(cat multidist.buildinfo)
  for t in multidist*.tar.gz; do
    tar --overwrite -xvzf $t
  done
  rm multidist*.tar.gz || true
  export rootwp=$(pwd)

  for release in $MULTI_DIST; do
    echo "Repo-ing for $release"

    cd "$rootwp/mbuild/$release"
    mkdir $BASE_PATH || true
    for suffix in gz bz2 xz deb dsc changes ddeb; do
      mv *.${suffix} $BASE_PATH || true
    done

    if ! aptly repo show $release; then
      aptly repo create -distribution="$release" $release
      aptly publish repo $release filesystem:repo:main
    fi
    aptly repo include -repo="$release" $BASE_PATH
    aptly publish update $release filesystem:repo:main
  done
else
  release=$(cat branch.buildinfo)

  mkdir -p $BASE_PATH
  for suffix in gz bz2 xz deb dsc changes ddeb; do
    mv *.${suffix} $BASE_PATH || true
  done

  if ! aptly repo show $release; then
    aptly repo create -distribution="$release" $release
    aptly publish repo $release filesystem:repo:main
  fi
  aptly repo include -repo="$release" $BASE_PATH
  aptly publish update $release filesystem:repo:main
fi
