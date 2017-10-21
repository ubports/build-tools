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

export release=$(cat branch.buildinfo)
export distribution=$(cat distribution.buildinfo)
export architecture="armhf"
export REPOS="$release"

mkdir -p binaries

for suffix in gz bz2 xz deb dsc changes ; do
  mv *.${suffix} binaries/ || true
done

export BASE_PATH="binaries/"
export PROVIDE_ONLY=true
export SUDO_CMD=sudo
/usr/bin/build-and-provide-package
