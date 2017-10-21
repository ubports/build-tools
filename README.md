# build-tools

These are used to build deb packages with our jenkins server

uses jenkins-debian-glue and jenkins blue ocean (jenkinsfile)

Use the Jenkinsfile here as reference

### How build system works

Builds will be automatically built and published to http://repo.ubports.com/

Branch name will decide where the builds land in our repo

```
http://repo.ubports.com/dists/[branch name]
```

###### Example:

- vivid lands in http://repo.ubports.com/dists/vivid/
- vivid-dev lands in http://repo.ubports.com/dists/vivid-dev/

- xenial lands in http://repo.ubports.com/dists/xenial/
- xenial-dev lands in http://repo.ubports.com/dists/xenial-dev/

#### How to add repo to the device

in file /etc/apt/sources.list add

```
deb http://repo.ubports.com/ [branch name] main
```

##### Example:

```
deb http://repo.ubports.com/ vivid main
```

### How to add project to Jenkins

- Add Jenkinsfile to root of project (find jenkinsfile in this repo)
- Login to ci.ubports.com
- Press `Open Blue Ocean`
- Press `New pipeline`
- Select `Github`
- Select `UBports`
- Select `New Pipeline`
- Find and select repository
- Press `Create pipeline`

### Limitations:

- Don't use `-` in version names (debian/changelog)
- Don't use source format `3.0 quit`

### Depend on other repos:
By default it will add itself and ubuntu-stable-phone ppa

#### Using "branch extension"

Branch extension is a quick and simple way to create packages that depend on
other packages in a different repo instead of rebulding all packaged,
you can simply create a "branch extension" like this:
```
[depend repo]+[branch name]
```

Example:

```
xenial+awesometest
```

#### Using ubports.depend file

Using file is a more permanent way to add depending repos, add one repo per line

Example:

```
xenial
xenial-caf
```
