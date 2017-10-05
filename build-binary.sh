export BUILD_ONLY=true
export DEB_BUILD_OPTIONS="parallel=$(nproc) nocheck"
export distribution=$(cat distribution.buildinfo)

/usr/bin/build-and-provide-package
