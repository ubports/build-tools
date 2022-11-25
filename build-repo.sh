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

if [ -f multidist.buildinfo ]; then
  echo "Doing multibuild"
  MULTI_DIST=$(cat multidist.buildinfo)
  for t in multidist*.tar.gz ; do
    tar --overwrite -xvzf "$t"
  done
  rm multidist*.tar.gz || true
  rootwp=$(pwd)
  export rootwp

  for d in $MULTI_DIST ; do
    echo "Repo-ing for $d"
    cd "$rootwp/mbuild/$d"

    release="$(cat ubports.target_apt_repository.buildinfo)"
    distribution=$d
    export release distribution

    if ! aptly -db-open-attempts=400 repo show "$release" ; then
      aptly -db-open-attempts=400 repo create -distribution="$release" "$release"
      aptly -db-open-attempts=400 publish repo -origin='UBports' "$release" filesystem:repo:main
    fi
    aptly -db-open-attempts=400 repo include -repo="$release" .
    aptly -db-open-attempts=400 publish update "$release" filesystem:repo:main

    cd "$rootwp"
    done
else
  release="$(cat ubports.target_apt_repository.buildinfo)"
  distribution=$(cat distribution.buildinfo)
  export release distribution

  # Publish built packages to Aptly repo.
  if ! aptly -db-open-attempts=400 repo show "$release" ; then
    aptly -db-open-attempts=400 repo create -distribution="$release" "$release"
    aptly -db-open-attempts=400 publish repo -origin='UBports' "$release" filesystem:repo:main
  fi

  aptly -db-open-attempts=400 repo include -repo="$release" .
  aptly -db-open-attempts=400 publish update "$release" filesystem:repo:main
fi
