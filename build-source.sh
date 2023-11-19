#!/bin/bash

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

# https://stackoverflow.com/a/8063398
# Usage: contains aList anItem
contains() {
    [[ $1 =~ (^|[[:space:]])$2($|[[:space:]]) ]] && return 0 || return 1
}

pr_repo_naming() {
  local GIT_URL GIT_REPO_NAME

  GIT_URL=$(cd source && git remote get-url origin)
  GIT_REPO_NAME="$(basename "${GIT_URL%.git}")"

  echo "PR_${GIT_REPO_NAME}_${CHANGE_ID}"
}

# Multi distro, set here to build master for multripple distros!
MULTIDIST_BRANCHES="main master ubports/latest ubports/contrib"
# Contains the distribution name and versioning suffix
BUILD_DISTS_MULTI="\
focal ubports20.04
"

VALID_DISTS_UBUNTU="xenial bionic focal jammy lunar"
VALID_DISTS_DEBIAN="buster bullseye sid"
VALID_DISTS="$VALID_DISTS_UBUNTU $VALID_DISTS_DEBIAN"

VALID_ARCHS="armhf arm64 amd64"

if [ ! "$SKIP_MOVE" = "true" ]; then
        tmp=$(mktemp -d)
        mv ./* ./.* "$tmp/"
        mv "$tmp" ./source
fi

ls source

set -ex

cd source
if [ -f .gitmodules ]; then
  git submodule update --init --recursive
fi
GIT_COMMIT=$(git rev-parse HEAD)
export GIT_COMMIT
export GIT_BRANCH="$BRANCH_NAME"
cd ..

source_format=$(cat source/debian/source/format)
if [[ $source_format != 3.0* ]]; then
   echo "WARNING: Please upgrade debian source format to 3.0"
fi

source_location_file=$(sourcedebian_or_source ubports.source_location)
if [ -n "$source_location_file" ]; then
  echo "WARNING: ubports.source_location file is deprecated, please use debian/watch file"
  while read -r SOURCE_URL && read -r SOURCE_FILENAME; do
    if [ -f "$SOURCE_FILENAME" ]; then
      rm "$SOURCE_FILENAME"
    fi

    wget -O "$SOURCE_FILENAME" "$SOURCE_URL"
  done <"$source_location_file"
  is_quilt=1;
elif [[ $source_format == "3.0 (quilt)" ]]; then
  cd source
  uscan --noconf --force-download --rename --download-current-version --destdir=..
  cd ..
  is_quilt=1;
fi

if [ -n "$is_quilt" ]; then
  export IGNORE_GIT_BUILDPACKAGE=true
  # FIXME: This relies on UBports-specific change to generate-git-snapshot.
  # Maybe using PRE_SOURCE_HOOK, but it accepts shell script file path and
  # that means we have to locate the path of ourself.
  export SKIP_PRE_CLEANUP=true

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
if contains "$MULTIDIST_BRANCHES" "$GIT_BRANCH" || \
    ([ -n "$CHANGE_TARGET" ] && contains "$MULTIDIST_BRANCHES" "$CHANGE_TARGET"); then
  echo "Doing multi build!"
  # Pre-fetch git branches from the remote, so that we can check if the
  # branches exist without hitting rate limit (see below).
  # Output of git ls-remote looks like this:
  # c689be1d07b1aca7d880f43115b143e3299f0793        refs/heads/master
  remote_branches=$( { cd source && git ls-remote --heads origin ; } || true)
  while read -r d dist_suffix ; do
    # Check if the distro-specific branch exists.
    if echo "$remote_branches" | grep -E -q "refs/heads(/ubports)?/${d}\$"; then
      echo "Branch ubports/$d exists, skip multidist build for $d"
      continue
    else
      built_distro="${built_distro} ${d}"
    fi

    echo "Gen git snapshot for $d"
    export DIST="$d"
    # FIXME: remove this when we stop using our custom version of `generate-git-snapshot`
    export DIST_OVERRIDE="$DIST"
    # This will be appended to the version number, after a '+'.
    export distribution=$dist_suffix

    # Versioning decision override for PR
    # TODO: might want to refactor this and the version below.
    changelog_dist=$(dpkg-parsechangelog -l source/debian/changelog --show-field Distribution)
    changelog_version=$(dpkg-parsechangelog -l source/debian/changelog --show-field Version)

    if [ "$changelog_dist" = "UNRELEASED" ]; then
      # generate-git-snapsnot does the right thing for unreleased version.
      : This branch intentionally left blank.
    elif [ -n "$CHANGE_TARGET" ]; then
      cd source/
      if git diff --stat "origin/${CHANGE_TARGET}..HEAD" | grep -q '^ debian/changelog '; then
        # A PR is, by definition, prerelease. Add a new changelog entry with UNRELEASED distro so that when
        # the released version comes out (which is when this PR gets merged), this version won't trump the release.
        # generate-git-snapshot will append the timestamp and git commit.
        dch --newversion="$changelog_version" --force-bad-version --distribution=UNRELEASED -- ""
      fi
      cd ../
    fi

    export UNRELEASED_APPEND_COMMIT=true
    generate-git-snapshot
    mkdir -p "mbuild/$d"
    mv ./*+"${dist_suffix}"* "mbuild/$d"
    unset DIST
    # FIXME: remove this when we stop using our custom version of `generate-git-snapshot`
    unset DIST_OVERRIDE

    # Specify which repo we want the package to land, as we now support MRs.
    if [ -n "$CHANGE_TARGET" ]; then
      target_repo="${d}_-_$(pr_repo_naming)"
    else
      target_repo="$d"
    fi
    echo "$target_repo" >"mbuild/$d/ubports.target_apt_repository.buildinfo"

    # For MRs, support specifying build dependency MRs. This should ideally be
    # read from GitLab's MR dependencies, but for now there's no API for it
    # (yet) [1]. For now, we read ubports.depends.
    #
    # The format is a little different though. We support specifying MRs in form
    # of PR_<repo>_<MR num>  only. We'll prepend 'xenial' or 'focal' for the
    # current multidist target and put it in proper ubports.depends for
    # generate_repo_extra.py to consume.
    #
    # Another catch is that the dependent MR has to also be multidist. If that's
    # not the case, it'll fail in the process of installing dependencies.
    #
    # [1] https://gitlab.com/gitlab-org/gitlab/-/issues/12551

    if [ -e buildinfos/ubports.depends.buildinfo ]; then
      if [ -z "$CHANGE_TARGET" ]; then
        echo "Error: ubports.depends is not supposed to be used for the main branch."
        exit 1
      fi

      while read -r dependency; do
        if ! [[ "$dependency" =~ ^PR_[a-zA-Z0-9_-]+_[0-9]+$ ]]; then
          echo "Error: ubports.depends line is malformed. Don't specify" \
               "distro prefix for main-branch MR. The line is: ${dependency}"
          exit 1 
        fi

        echo "${d}_-_${dependency}" >> "mbuild/${d}/ubports.depends"
      done <buildinfos/ubports.depends.buildinfo
    fi
  done < <(printf '%s' "$BUILD_DISTS_MULTI")
  tar -zcvf multidist.tar.gz mbuild

  if [ -z "$built_distro" ]; then
    echo "No distro is included in multidist. Maybe \"$GIT_BRANCH\" shouldn't exist?"
    exit 1
  fi

  # "# " removes leading space from $built_distro.
  echo "${built_distro# }" > multidist.buildinfo
else
  if [ -n "$CHANGE_ID" ]; then
    # This is a PR. Publish each PR for each project into its own repository
    REPOS="$(pr_repo_naming)"

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
    # generate-git-snapsnot does the right thing for unreleased version.
    : This branch intentionally left blank.
  elif [ -n "$CHANGE_TARGET" ]; then
    cd source/
    git fetch origin "${CHANGE_TARGET}"
    if git diff --stat "origin/${CHANGE_TARGET}..HEAD" | grep -q '^ debian/changelog '; then
      # A PR is, by definition, prerelease. Add a new changelog entry with UNRELEASED distro so that when
      # the released version comes out (which is when this PR gets merged), this version won't trump the release.
      # generate-git-snapshot will append the timestamp and git commit.
      dch --newversion="$changelog_version" --force-bad-version --distribution=UNRELEASED -- ""
    fi
    cd ../
  elif (cd source && git show --stat --pretty=format: HEAD|grep -q '^ debian/changelog '); then
    # The last commit touch the changelog; assumes the it's the releasing commit
    if $is_releasing_repo; then
      # Special treatment for releasing repo; You release a version, and your version is being released!
      export SKIP_DCH=true
    else
      # When working in branch like xenial_-_qt-5-12, we don't know if this will get PR'ed into the releasing
      # branch or not. To ensure version uniqueness, we also have to treat this also as a PR too.
      # FIXME: This can have a weird quirk that a package can skips from a prerelease to a snapshot.
      # This hopefully should be rare.
      (cd source && dch --newversion="$changelog_version" --force-bad-version --distribution=UNRELEASED -- "")
    fi
  else
    # This repo does not increase the changelog version. Use generate-git-snapshot's normal snapshot versioning.
    # This is done by leaving the Debian changelog alone.
    : This branch intentionally left blank.
  fi

  export TIMESTAMP_FORMAT="$d%Y%m%d%H%M%S"
  export UNRELEASED_APPEND_COMMIT=true
  generate-git-snapshot
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
