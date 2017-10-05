export release=$(cat distribution.buildinfo)
export distribution=$(cat distribution.buildinfo)
mkdir -p binaries

for suffix in gz bz2 xz deb dsc changes ; do
  mv *.${suffix} binaries/ || true
done

export BASE_PATH="binaries/"
export PROVIDE_ONLY=true
/usr/bin/build-and-provide-package
