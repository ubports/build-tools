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


# Multi distro, set here to build master for multripple distros!
MULTI_DIST="xenial bionic"

DIST="vivid xenial artful bionic"
DIST_DEV="vivid-dev xenial-dev"

if [ ! "$SKIP_MOVE" = "true" ]; then
        tmp=$(mktemp -d)
        mv * .* $tmp/
        mv $tmp ./source
fi

ls source

set -ex

cd source
if [ -f .gitmodules ]; then
  git submodule update --init --recursive
fi
export GIT_COMMIT=$(git rev-parse HEAD)
export GIT_BRANCH=$BRANCH_NAME
cd ..

if [ -f source/ubports.source_location ]; then
  while read -r SOURCE_URL && read -r SOURCE_FILENAME; do
    if [ -f "$SOURCE_FILENAME" ]; then
      rm "$SOURCE_FILENAME"
    fi

    wget -O "$SOURCE_FILENAME" "$SOURCE_URL"
  done <source/ubports.source_location

  export IGNORE_GIT_BUILDPACKAGE=true
  export USE_ORIG_VERSION=true
  export SKIP_DCH=true
  export SKIP_PRE_CLEANUP=true
  export SKIP_GIT_CLEANUP=true
  rm source/Jenkinsfile || true
  rm source/ubports.source_location || true
fi

if echo $DIST | grep -w $GIT_BRANCH > /dev/null; then
        echo "This is on a release branch, overriding dist to $GIT_BRANCH"
        export DIST_OVERRIDE=$GIT_BRANCH
fi
if echo "vivid-dev" | grep -w $GIT_BRANCH > /dev/null; then
        echo "This is on a release branch, overriding dist to vivid"
        export DIST_OVERRIDE="vivid"
fi
if echo "xenial-dev" | grep -w $GIT_BRANCH > /dev/null; then
        echo "This is on a release branch, overriding dist to xenial"
        export DIST_OVERRIDE="xenial"
fi

# Multi dist build for "master" only
# We might want to expand this to allow PR's to build like this
if [ "$GIT_BRANCH" == "master" ]; then
  echo "Doing multi build!"
  for d in $MULTI_DIST ; do
    echo "Gen git snapshot for $d"
    export TIMESTAMP_FORMAT="$d%Y%m%d%H%M%S"
    export DIST_OVERRIDE="$d"
    /usr/bin/generate-git-snapshot
    mkdir -p "mbuild/$d"
    mv *+0~$d* "mbuild/$d"
    rm mbuild/$d/*.changes || true
    unset TIMESTAMP_FORMAT
    unset DIST_OVERRIDE
  done
  tar -zcvf multidist.tar.gz mbuild
  echo "$MULTI_DIST" > multidist.buildinfo
else
  export TIMESTAMP_FORMAT="$d%Y%m%d%H%M%S"
  /usr/bin/generate-git-snapshot
  rm *.changes
  echo "Gen git snapshot done"
fi

echo "$GIT_BRANCH" > branch.buildinfo

# If this is a pull request, we want to also use the target repository for
# dependency checking. To do so, add the name of the target branch (which is in
# the CHANGE_TARGET environment variable) to the ubports.depends file.
if [ -n "${CHANGE_TARGET}" ]; then
  echo "${CHANGE_TARGET}" >> source/ubports.depends
fi

if [ -f source/ubports.depends ]; then
        cp source/ubports.depends ubports.depends.buildinfo
fi
if [ -f source/ubports.no_test ]; then
        cp source/ubports.no_test ubports.no_test.buildinfo
fi
if [ -f source/ubports.backports ]; then
        cp source/ubports.backports ubports.backports.buildinfo
fi
