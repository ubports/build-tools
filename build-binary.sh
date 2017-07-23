export BUILD_ONLY=true
export DEB_BUILD_OPTIONS="parallel=$(nproc) nocheck"
/usr/bin/build-and-provide-package
