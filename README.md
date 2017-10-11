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
