
set -xe

export BUILD_ONLY=true
export DEB_BUILD_OPTIONS="parallel=$(nproc) nocheck"
export distribution=$(cat distribution.buildinfo)

generate_repo_extra.py
if [ -f ubports.repos_extra ]; then
  export REPOSITORY_EXTRA=$(cat ubports.repos_extra)
  export REPOSITORY_EXTRA_KEYS="http://repo.ubports.com/keyring.gpg"
  echo "INFO: Adding extra repo $REPOSITORY_EXTRA"
fi

/usr/bin/build-and-provide-package
