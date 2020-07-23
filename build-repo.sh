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

push_aptly() {
    local release="$1"
    local path="$2"

    echo "[APT] Pushing packages to $release repo"

    if ! aptly -db-open-attempts=40 repo show $release ; then
      aptly -db-open-attempts=40 repo create -distribution="$release" $release
      aptly -db-open-attempts=40 publish repo $release filesystem:repo:main
    fi
    aptly -db-open-attempts=40 repo include -repo="$release" "$path"
    aptly -db-open-attempts=40 publish update $release filesystem:repo:main
}

if [ -f multidist.buildinfo ]; then
  echo "[APT] Doing multi-dist push"

  MULTI_DIST=$(cat multidist.buildinfo)
  for t in multidist*.tar.gz ; do
    tar --overwrite -xvzf $t
    rm $t || true
  done

  for release in $MULTI_DIST ; do
    workspace="$(pwd)/mbuild/$release"

    push_aptly "$release" "$workspace"
  done
else
  echo "[APT] Doing single-dist push"

  release="$(cat ubports.target_apt_repository.buildinfo)"

  push_aptly "$release" "$(pwd)"
fi
