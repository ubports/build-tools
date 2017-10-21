
set -e

DIST="vivid xenial"
DIST_DEV="vivid-dev xenial-dev"

if [ ! "$SKIP_MOVE" = "true" ]; then
	tmp=$(mktemp -d)
	mv * .* $tmp/
	mv $tmp ./source
fi

ls source

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
if echo $DIST | grep -w $GIT_BRANCH > /dev/null; then
	echo "dputing"
	dput ppa:ubports-developers/overlay *.changes
fi
if echo $DIST_DEV | grep -w $GIT_BRANCH > /dev/null; then
	echo "dev dputing"
	dput ppa:ubports-developers/overlay-dev *.changes
fi
rm *.changes
