#!/bin/sh

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

# Parallel option is overwritten by build-and-provide-package anyway, but in
# case we switch from it, let's leave it in.

DEB_BUILD_OPTIONS="parallel=$(nproc)"
DEB_BUILD_PROFILES=""

if [ -f ubports.no_test.buildinfo ]; then
	DEB_BUILD_OPTIONS="${DEB_BUILD_OPTIONS} nocheck"
	DEB_BUILD_PROFILES="${DEB_BUILD_PROFILES} nocheck"

	rm ubports.no_test.buildinfo
fi

if [ -f ubports.no_doc.buildinfo ]; then
	DEB_BUILD_OPTIONS="${DEB_BUILD_OPTIONS} nodoc"
	DEB_BUILD_PROFILES="${DEB_BUILD_PROFILES} nodoc"

	rm ubports.no_doc.buildinfo
fi

# Allow setting additional build profiles. Useful for bootstraping
# circular dependencies.
if [ -f ubports.build_profiles.buildinfo ]; then
	DEB_BUILD_PROFILES="${DEB_BUILD_PROFILES} $(cat ubports.build_profiles.buildinfo)"

	rm ubports.build_profiles.buildinfo
fi

export DEB_BUILD_OPTIONS DEB_BUILD_PROFILES

if [ -f ubports.depends.buildinfo ]; then
	mv ubports.depends.buildinfo ubports.depends
fi
generate_repo_extra.py
if [ -f ubports.repos_extra ]; then
  export REPOSITORY_EXTRA="$(cat ubports.repos_extra)"
  export REPOSITORY_EXTRA_KEYS="https://repo.ubports.com/keyring.gpg"
  echo "INFO: Adding extra repo $REPOSITORY_EXTRA"
fi

if [ -f ubports.architecture.buildinfo ]; then
  THIS_ARCH=$(dpkg --print-architecture)
	REQUEST_ARCH=$(cat ubports.architecture.buildinfo)
	if [ ! "$THIS_ARCH" = "$REQUEST_ARCH" ]; then
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

	. /etc/jenkins/debian_glue
	for d in $MULTI_DIST ; do
		debsign -k"${KEY_ID:-}" "mbuild/$d/"*.changes
	done

	tar -zcvf multidist-$architecture-$RANDOM.tar.gz mbuild
else
	export distribution=$(cat distribution.buildinfo)
	/usr/bin/build-and-provide-package

	. /etc/jenkins/debian_glue
	debsign -k"${KEY_ID:-}" *.changes
fi
