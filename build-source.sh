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

DIST="vivid xenial"
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
  rm $(head -n 2 source/ubports.source_location | tail -1) || true
  wget -O $(head -n 2 source/ubports.source_location | tail -1) $(head -n 1 source/ubports.source_location)
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
/usr/bin/generate-git-snapshot
echo "Gen git snapshot done"

# Disable ppa since ppa does not build vivid anymore....
#if echo $DIST | grep -w $GIT_BRANCH > /dev/null; then
#        echo "dputing"
        #dput ppa:ubports-developers/overlay *.changes
#fi
#if echo $DIST_DEV | grep -w $GIT_BRANCH > /dev/null; then
#        echo "dev dputing"
        #dput ppa:ubports-developers/overlay-dev *.changes
#fi

rm *.changes
echo "$GIT_BRANCH" > branch.buildinfo

# If this is a pull request, we want to also use the target repository for
# dependency checking. To do so, add the name of the target branch (which is in
# the CHANGE_TARGET environment variable) to the ubports.depends file.
if [ -n "${CHANGE_TARGET}" ]; then
  echo "${CHANGE_TARGET}" >> ubports.depends
fi
