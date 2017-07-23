DIST="vivid xenial"

tmp=$(mktemp -d)
mv * .* $tmp/
mv $tmp ./source

ls source

cd source
export GIT_COMMIT=$(git rev-parse HEAD)
export GIT_BRANCH=$BRANCH_NAME
cd ..
/usr/bin/generate-git-snapshot
if echo $DIST | grep -w $GIT_BRANCH > /dev/null; then
	echo "dputing"
	dput ppa:ubports-developers/overlay *.changes
fi
rm *.changes
