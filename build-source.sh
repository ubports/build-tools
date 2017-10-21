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
export GIT_COMMIT=$(git rev-parse HEAD)
export GIT_BRANCH=$BRANCH_NAME
cd ..

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
