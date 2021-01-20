#!/bin/sh

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

# Accepts file paths. Print the first file that exists, or nothing if none exists.
first_existing_file () {
  while [ -n "$1" ]; do
    if [ -e "$1" ]; then
      echo "$1"
      return
    fi

    shift
  done
}

sourcedebian_or_source () {
  first_existing_file "source/debian/${1}" "source/${1}"
}

# Multi distro, set here to build master for multripple distros!
BUILD_DISTS_MULTI="xenial focal"

VALID_DISTS_UBUNTU="xenial bionic focal groovy"
VALID_DISTS_DEBIAN="buster bullseye sid"
VALID_DISTS="$VALID_DISTS_UBUNTU $VALID_DISTS_DEBIAN"

VALID_ARCHS="armhf arm64 amd64"

if [ ! "$SKIP_MOVE" = "true" ]; then
        tmp=$(mktemp -d)
        mv * .* $tmp/
        mv $tmp ./source
fi

ls source

set -ex

cd source
if [ -f .gitmodules ]; then
  git submodule update --init --recursive
fi
export GIT_COMMIT=$(git rev-parse HEAD)
export GIT_BRANCH=$BRANCH_NAME
cd ..

source_location_file=$(sourcedebian_or_source ubports.source_location)
if [ -n "$source_location_file" ]; then
  while read -r SOURCE_URL && read -r SOURCE_FILENAME; do
    if [ -f "$SOURCE_FILENAME" ]; then
      rm "$SOURCE_FILENAME"
    fi

    wget -O "$SOURCE_FILENAME" "$SOURCE_URL"
  done <"$source_location_file"

  export IGNORE_GIT_BUILDPACKAGE=true
  # Always include the original source in the .changes file.
  # Ideally we should do this only when we have a new upstream version, but
  # I'm too lazy to check if a source package is already in the repo.
  # This is primarily to please Aptly, and Aptly seems to check for file
  # duplication anyway. (see dpkg-genchanges manpage)
  export DBP_EXTRA_OPTS="-sa"

  rm "$source_location_file" || true
  existing_file=$(sourcedebian_or_source Jenkinsfile)
  if [ -n "$existing_file" ]; then
    rm "$existing_file" || true
  fi
fi

# Move files controlling the build process under UBports CI to a directory.
# This prevents dpkg-buildpackage from error out and generate-git-snapshot from
# removing these files during there cleanup process.
mkdir -p buildinfos
for file in \
    ubports.depends \
    ubports.no_test \
    ubports.no_doc \
    ubports.build_profiles \
    ubports.backports \
  ; do
  existing_file=$(sourcedebian_or_source "$file")
  if [ -n "$existing_file" ]; then
    # Move them out of the way so that dpkg-buildpackage won't trip.
    # (And to allow us to inspect the file without extracting debian package
    # in the next step)
    mv "$existing_file" "buildinfos/${file}.buildinfo"
  fi
done

# Skip git cleanup, or those files will come back and/or our modification
# to debian/changelog will be overwritten (see below).
export SKIP_GIT_CLEANUP=true

# Multi dist build for "master" only
# We might want to expand this to allow PR's to build like this
if [ "$GIT_BRANCH" = "master" ]; then
  echo "Doing multi build!"
  for d in $BUILD_DISTS_MULTI ; do
    echo "Gen git snapshot for $d"
    export TIMESTAMP_FORMAT="$d%Y%m%d%H%M%S"
    export DIST="$d"
    # FIXME: remove this when we stop using our custom version of `generate-git-snapshot`
    export DIST_OVERRIDE="$DIST"
    /usr/bin/generate-git-snapshot
    mkdir -p "mbuild/$d"
    mv *+0~$d* "mbuild/$d"
    unset TIMESTAMP_FORMAT
    unset DIST
    # FIXME: remove this when we stop using our custom version of `generate-git-snapshot`
    unset DIST_OVERRIDE
  done
  tar -zcvf multidist.tar.gz mbuild
  echo "$BUILD_DISTS_MULTI" > multidist.buildinfo
else
  if [ -n "$CHANGE_ID" ]; then
    # This is a PR. Publish each PR for each project into its own repository

    if [ -n "$GIT_URL" ]; then
      echo "DEBUG: \$GIT_URL is ${GIT_URL}"
    elif [ -n "$GIT_URL_1" ]; then
      echo "DEBUG: Set \$GIT_URL to \$GIT_URL_1, which is ${GIT_URL_1}"
      GIT_URL=$GIT_URL_1
    else
      GIT_URL=$( (cd source && git remote get-url origin) || true)
      echo "DEBUG: Set \$GIT_URL to git repo's origin remote url, which is ${GIT_URL}"
    fi

    if [ -n "$GIT_URL" ]; then
      GIT_REPO_NAME="$(basename "${GIT_URL%.git}")"
    else
      echo "Cannot determine git repo name. Try to use the job name instead." \
          "May produce incorrect apt repository name."
      GIT_REPO_NAME=$JOB_BASE_NAME
    fi

    REPOS="PR_${GIT_REPO_NAME}_${CHANGE_ID}"

    # We want the target branch to be part of our repo dependency (in addition to
    # what's specified in ubports.depends)
    # TODO: support specifying PRs as a dependency in the PR body.

    if [ -n "${CHANGE_TARGET}" ]; then
      # Remove "ubports/" prefix if present
      CHANGE_TARGET_REPO="${CHANGE_TARGET#ubports/}"
      echo "$CHANGE_TARGET_REPO" >> buildinfos/ubports.depends.buildinfo
    fi
  else
    # Support both ubports/xenial(_-_.*)? and xenial(_-_.*)?
    REPOS="${GIT_BRANCH#ubports/}"

    # Parse branch architecture extension
    if echo "$REPOS" | grep -q '@[a-z]*$'; then
      REQUEST_ARCH="${REPOS#*@}"
      REPOS="${REPOS%@*}"
    fi
  fi

  # Decides which distribution the snapshot is released to (affects base rootfs selection for building).
  if [ -n "$CHANGE_ID" ]; then
    branch_dist=${CHANGE_TARGET_REPO%%_-_*}
  else
    branch_dist=${REPOS%%_-_*}
  fi
  changelog_dist=$(dpkg-parsechangelog -l source/debian/changelog --show-field Distribution)
  changelog_version=$(dpkg-parsechangelog -l source/debian/changelog --show-field Version)

  if ! echo "$VALID_DISTS" | grep -q -w "$branch_dist"; then
    echo "Branch name (or merge target) does not contain valid distribution. Using distribution from changelog." \
         "Note that repo dependencies might not work correctly."
    DIST="$changelog_dist"
  else
    echo "Using distribution from branch name (or merge target)."
    DIST="$branch_dist"

    if [ "$changelog_dist" != "UNRELEASED" ] && [ "$changelog_dist" != "$branch_dist" ]; then
      echo "Note: distribution in changelog (${changelog_dist}) does not match branch's distribution (${branch_dist})."
    fi
  fi

  if ! echo "$VALID_DISTS" | grep -q -w "$DIST"; then
    echo "ERROR: Distribution '${DIST}' is not a valid distribution for this CI."
    exit 1
  fi

  export DIST
  # FIXME: remove this when we stop using our custom version of `generate-git-snapshot`
  export DIST_OVERRIDE="$DIST"

  is_releasing_repo=$(echo "$VALID_DISTS" | grep -q -w "$REPOS" && echo true || echo false)

  # Versioning decision override for PR and releasing branch
  if [ "$changelog_dist" = "UNRELEASED" ]; then
    # If the repo we're publishing is the distro name by itself, we don't allow UNRELEASED change.
    if $is_releasing_repo; then
      echo "ERROR: trying to publish UNRELEASD version to a releasing repo \"${REPOS}\"."
      exit 1
    fi

    # Make sure non-PR unreleased looks like PR unreleased. See below.
    (cd source && debchange --newversion "${changelog_version}~prerelease" --force-bad-version -- "")
  elif [ -n "$CHANGE_TARGET" ] && (cd source && git diff --stat "${CHANGE_TARGET}..HEAD" | grep -q '^ debian/changelog '); then
    # A PR is, by definition, prerelease. Set the version as such so that when the released version comes
    # out (which is when this PR gets merged), this version won't trump the release. generate-git-snapshot
    # will append the timestamp and git commit.
    (cd source && debchange --newversion "${changelog_version}~prerelease" --force-bad-version -- "")
  elif (cd source && git show --stat --pretty=format: HEAD|grep -q '^ debian/changelog '); then
    # The last commit touch the changelog; assumes the it's the releasing commit
    if $is_releasing_repo; then
      # Special treatment for releasing repo; You release a version, and your version is being released!
      export SKIP_DCH=true
    else
      # When working in branch like xenial_-_qt-5-12, we don't know if this will get PR'ed into the releasing
      # branch or not. To ensure version uniqueness, we also have to treat this also as a prerelease too.
      # FIXME: This can have a weird quirk that a package can skips from a prerelease to a snapshot.
      # This hopefully should be rare.
      (cd source && debchange --newversion "${changelog_version}~prerelease" --force-bad-version -- "")
    fi
  else
    # This repo does not increase the changelog version. Use generate-git-snapshot's normal snapshot versioning.
    # This is done by leaving the Debian changelog alone.
    : This branch intentionally left blank.
  fi

  export TIMESTAMP_FORMAT="$d%Y%m%d%H%M%S"
  export UNRELEASED_APPEND_COMMIT=true
  /usr/bin/generate-git-snapshot
  echo "Gen git snapshot done"

  echo "$REPOS" >buildinfos/ubports.target_apt_repository.buildinfo
  if [ -n "$REQUEST_ARCH" ]; then
    if echo "$VALID_ARCHS" | grep -q "$REQUEST_ARCH"; then
      echo "$REQUEST_ARCH" >buildinfos/ubports.architecture.buildinfo
    else
      echo "ERROR: Arch '${REQUEST_ARCH}' is not valid"
      exit 1
    fi
  fi

  # Convey the distribution of choice (used by build-binary.sh).
  # It was in our custom generate-git-snapshot, but now we bring it out so that
  # we don't have to rely on hidden modification.
  echo "$DIST" > distribution.buildinfo
fi

# Move buildinfos back to the workspace root, so that they'll be stashed.
mv buildinfos/* . || true
rm -rf buildinfos || true
