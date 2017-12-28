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


set -ex

export PYTHONIOENCODING=UTF-8
export BUILD_ONLY=true
export DEB_BUILD_OPTIONS="parallel=$(nproc) nocheck"
export distribution=$(cat distribution.buildinfo)

generate_repo_extra.py
if [ -f ubports.repos_extra ]; then
  export REPOSITORY_EXTRA="$(cat ubports.repos_extra)"
  export REPOSITORY_EXTRA_KEYS="http://repo.ubports.com/keyring.gpg"
  echo "INFO: Adding extra repo $REPOSITORY_EXTRA"
fi

/usr/bin/build-and-provide-package
