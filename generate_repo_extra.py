#!/usr/bin/python3

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

import requests
import os
import sys

DEB_SOURCE_TEMPLATE = "deb http://repo.ubports.com/ %s main"
VALID_ARCH = ["armhf", "arm64", "amd64"]


def repo_exist(repo):
    r = requests.get("http://repo.ubports.com/dists/%s/Release" % repo)
    return r.status_code == 200


def get_branch():
    if not os.path.isfile("branch.buildinfo"):
        print("ERROR: branch.buildinfo does not exist!")
        sys.exit(1)
        return
    with open("branch.buildinfo") as f:
        branch = f.read()
    return branch.strip()


def ubports_depends_exist():
    return os.path.isfile("ubports.depends")


def get_ubports_depends():
    if not ubports_depends_exist():
        return
    with open("ubports.depends") as f:
        depend = f.readlines()

    # Overflow check
    if len(depend) > 20:
        print("ERROR: depend overflow size %s" % len(depend))
        return

    depend = [x.strip() for x in depend]
    return depend


def is_arch_ext(branch):
    return "@" in branch


def arch_extension_get_base_branch(branch):
    if not is_arch_ext(branch):
        return
    return branch.split("@")[0]


def arch_extension_get_arch(branch):
    if not is_arch_ext(branch):
        return
    return branch.split("@")[-1]


def is_arch_valid(arch):
    return arch in VALID_ARCH


def is_extension(branch):
    return "_-_" in branch


def extension_get_repos(branch):
    if not is_extension(branch):
        return
    split_list = branch.split("_-_")
    branches = [split_list[0]]
    for i in split_list[1:-1]:
        branches.append("%s_-_%s" % (branches[-1], i))
    return branches


depends_list = []

branch = get_branch()

# Extension arch
if is_arch_ext(branch):
    arch = arch_extension_get_arch(branch)
    branch = arch_extension_get_base_branch(branch)
    if is_arch_valid(arch):
        print("Arch %s" % arch)
        with open("ubports.architecture", "w") as f:
            f.write(arch)
        with open("branch.buildinfo", "w") as f:
            f.write(branch)
    else:
        print("ERROR: Arch '%s' is not valid" % arch)
        sys.exit(1)

# Working repo
if repo_exist(branch):
    depends_list.append(branch)
else:
    print("WARNING: branch repo '%s' does not exist, please ignore if this is a new branch" % branch)

# Extension repo
if is_extension(branch):
    base_extensions = extension_get_repos(branch)
    print(base_extensions)
    for base_extension in base_extensions:
        if repo_exist(base_extension):
            depends_list.append(base_extension)
        else:
            print("ERROR: Extension repo '%s' do not exist" % base_extension)
            sys.exit(1)

# Depends file
if ubports_depends_exist():
    depends_file = get_ubports_depends()
    if not depends_file:
        print("ERROR: get_ubports_depends failed")
        sys.exit(1)
    for _depend in depends_file:
        if repo_exist(_depend):
            depends_list.append(_depend)
        else:
            print("ERROR: ubports.depends repo '%s' do not exist" % _depend)
            sys.exit(1)

print("Branches %s " % depends_list)

deb_sources_list = []
for _depend in depends_list:
    deb_sources_list.append(DEB_SOURCE_TEMPLATE % _depend)

deb_sources = ",".join(deb_sources_list)

with open("ubports.repos_extra", "w") as f:
    f.write(deb_sources)
