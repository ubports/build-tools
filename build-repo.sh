export release="xenial"
mkdir -p binaries

for suffix in gz bz2 xz deb dsc changes ; do
  mv *.${suffix} binaries/ || true
done

export BASE_PATH="binaries/"
export PROVIDE_ONLY=true
/usr/bin/build-and-provide-package
