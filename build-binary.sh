#!/bin/bash
# Copyright (C) 2017,2018 Marius Gripsgard <marius@ubports.com>
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

set -ex

export PYTHONIOENCODING=UTF-8
export BUILD_ONLY=true

if [ -f ubports.no_test.buildinfo ]; then
	export DEB_BUILD_OPTIONS="parallel=$(nproc) nocheck"
	rm ubports.no_test.buildinfo
else
	export DEB_BUILD_OPTIONS="parallel=$(nproc)"
fi

if [ -f ubports.depends.buildinfo ]; then
	mv ubports.depends.buildinfo ubports.depends
fi
generate_repo_extra.py
if [ -f ubports.repos_extra ]; then
  export REPOSITORY_EXTRA="$(cat ubports.repos_extra)"
  export REPOSITORY_EXTRA_KEYS="http://repo.ubports.com/keyring.gpg"
  echo "INFO: Adding extra repo $REPOSITORY_EXTRA"
fi

if [ -f ubports.architecture ]; then
  THIS_ARCH=$(dpkg --print-architecture)
	REQUEST_ARCH=$(cat ubports.architecture)
	if [ ! "$THIS_ARCH" == "$REQUEST_ARCH" ]; then
		echo "My arch $THIS_ARCH does not match requested arch $REQUEST_ARCH, quiting"
		exit 0
	fi
fi

if [ -f multidist.buildinfo ]; then
	echo "Doing multibuild"
	MULTI_DIST=$(cat multidist.buildinfo)
	tar -xvzf multidist.tar.gz
	rm multidist.tar.gz
	export rootwp=$(pwd)

	for d in $MULTI_DIST ; do
		echo "Bulding for $d"
		export distribution=$d
		export REPOSITORY_EXTRA="deb http://repo.ubports.com/ $d main"
		export WORKSPACE="$rootwp/mbuild/$d"
		cd "$WORKSPACE"
		rm -r adt *.gpg || true
		/usr/bin/build-and-provide-package
		cd $rootwp
	done
	tar -zcvf multidist-$architecture-$RANDOM.tar.gz mbuild
else
	export distribution=$(cat distribution.buildinfo)
	/usr/bin/build-and-provide-package
fi
