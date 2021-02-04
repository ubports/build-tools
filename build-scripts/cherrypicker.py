#!/usr/bin/env python3

# Copyright (C) 2021 UBports Foundation
# Author: Ratchanan Srirattanamet <ratchanan@ubports.com>
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

# This script is used implement the "shadow branch" scheme, in which for every
# PR against main (or master), a branch will also be created under shadow/
# namespace, cherry-picking all commits in the PR onto the target branch [1].
# This intends to allow people to open a PR against main branch, and have them
# tested on the xenial branch as well.

import os
import re
import subprocess
import urllib.parse

import requests

# Configurations
MAIN_BRANCH_NAMES = {'main', 'master'}
# When we have the forked Focal, add it here
ALLOWED_SHADOW_TARGETS = {'ubports/xenial'}

CHERRYPICK_COMMITTER_NAME="UBports auto cherrypicker"
CHERRYPICK_COMMITTER_EMAIL="build@ubports.com" # FIXME: infrastructure team.

# This assumes that the repo is on hosted GitLab.
def get_gitlab_project_name():
    repo_url_run = subprocess.run(['git', 'remote', 'get-url', 'origin'],
                                capture_output=True, text=True, check=True)
    repo_url = repo_url_run.stdout

    repo_url_match = re.match(r'^https://gitlab.com/(?P<project_name>.+)\.git$', repo_url)
    project_name = repo_url_match.group('project_name')

    return project_name

def get_gitlab_mr_description(project_name: str, mr_iid: str):
    BASE_URL = 'https://gitlab.com/api/v4'

    project_name_quoted = urllib.parse.quote(project_name, safe='')
    res = requests.get(
        f'{BASE_URL}/projects/{project_name_quoted}/merge_requests/{mr_iid}',
        # For some reason Cloudflare considers Python-requests to be an invalid browser.
        headers={'user-agent': ''})
    mr = res.json()
    return mr['description']

def parse_git_trailer(text: str):
    # Get the last group of consecutive lines
    trailer = re.split('\n{2,}', text)[-1]

    kv: dict[str, str] = {}
    for line in trailer.splitlines():
        line_split = re.split(': ?', line, maxsplit=1)
        if len(line_split) != 2:
            # This trailer is malformed. Perhaps not a git trailer at all.
            return None
        kv[line_split[0]] = line_split[1]

    return kv

# This is the requirements of the script. Jenkinsfile is expected to skip this step
# if these conditions are not met.

change_id = os.environ['CHANGE_ID']
change_target = os.environ['CHANGE_TARGET']
if change_target not in MAIN_BRANCH_NAMES:
    raise RuntimeError("Cherrypicker invoked for the MR against non-main branches.")

change_head = subprocess.run(['git', 'rev-parse', 'HEAD'],
                                capture_output=True, text=True, check=True).stdout.strip()

# Parse MR's description from GitLab, to determine if we need to cherry-pick or not.
project_name = get_gitlab_project_name()
mr_desc = get_gitlab_mr_description(project_name, change_id)
trailer = parse_git_trailer(mr_desc)

try:
    pick_to = trailer['Pick-to']
except (TypeError, KeyError):
    print("This MR does not request cherry-picking. Exitting now...")
    exit(0)

shadow_targets = set(pick_to.split(' '))
if not shadow_targets.issubset(ALLOWED_SHADOW_TARGETS):
    raise RuntimeError((f"Cherry-pick targets {shadow_targets} is not a subset "
                        f"of the allowed branches ({ALLOWED_SHADOW_TARGETS}). "
                        f"Check the spelling and try again."))

shadow_branches = []
for shadow_target in shadow_targets:
    shadow_branch = f"shadow/{shadow_target}_-_MR-{change_id}"

    # Fetch the shadow target and create a branch of it.
    try:
        subprocess.run(f"""
            set -ex

            git fetch origin "{change_target}" "{shadow_target}"
            git checkout -b "{shadow_branch}" "origin/{shadow_target}"
        """, shell=True, check=True)
    except subprocess.CalledProcessError as err:
        print((f'Failed to fetch cherry-pick target "{shadow_target}". Most '
               f"likely the branch doesn't exist. Check if the branch exists "
               f"and try again."))
        raise err

    # Now perform the actual cherry-pick.
    # Don't rely on config on the machine/repo and specify the committer
    # directly. Also, get the hash into the commit message so that the shadow
    # branch's build knows which commit to report success/failure to.
    try:
        subprocess.run(f"""
            set -ex
            git \\
                -c "user.name={CHERRYPICK_COMMITTER_NAME}" \\
                -c "user.email={CHERRYPICK_COMMITTER_EMAIL}" \\
                cherry-pick -x "origin/{change_target}..{change_head}"
        """, shell=True, check=True)
    except subprocess.CalledProcessError as err:
        print((f"Cherry-picking this MR to \"{shadow_target}\" fails. Most likely reason"
               f"is that the patch(es) no longer applies to the target branch. Please "
               f"remove the cherry-pick footer from your MR, resolve the conflict "
               f"separately, and open a new MR."))
        raise err

    # If all is well, keep the name of the shadow branches so that we can push it.
    shadow_branches.append(shadow_branch)

# Now that everything is good, push the shadow branches so that the new
# pipeline(s) will be run.
# TODO: figure out the credential.
print(f"TODO: pushing branches {', '.join(shadow_branches)}")
