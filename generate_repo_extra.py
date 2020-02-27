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
import subprocess

REPO_BASE = "http://repo.ubports.com/"

DEB_SOURCE_TEMPLATE = "deb %s %s main"
CHECK_TEMPLATE = "%sdists/%s/Release"

MAIN = "http://archive.ubuntu.com/ubuntu/"
PORTS = "http://ports.ubuntu.com/ubuntu-ports/"
BACKPORTS = "deb {} xenial-backports main restricted universe"


def repo_exist(repo, base=REPO_BASE):
    r = requests.get(CHECK_TEMPLATE % (base, repo))
    return r.status_code == 200


def get_target_apt_repository():
    if not os.path.isfile("ubports.target_apt_repository.buildinfo"):
        print("ERROR: ubports.target_apt_repository.buildinfo does not exist!")
        sys.exit(1)
        return
    with open("ubports.target_apt_repository.buildinfo") as f:
        target_apt_repository = f.read()
    return target_apt_repository.strip()


def ubports_depends_exist():
    return os.path.isfile("ubports.depends")


def enable_backports():
    return os.path.isfile("ubports.backports.buildinfo")


def get_archive():
    arch = subprocess.check_output(
        ["dpkg", "--print-architecture"]).decode("utf8").strip()
    return MAIN if arch == "amd64" or arch == "i386" else PORTS


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

def is_extension(target_apt_repository):
    return "_-_" in target_apt_repository

def extension_get_repos(target_apt_repository):
    if not is_extension(target_apt_repository):
        return
    split_list = target_apt_repository.split("_-_")
    repos = [split_list[0]]
    for i in split_list[1:-1]:
        repos.append("%s_-_%s" % (repos[-1], i))
    return repos


depends_list = []

target_apt_repository = get_target_apt_repository()

base = REPO_BASE
if (target_apt_repository.startswith("focal")):
    base = "http://repo2.ubports.com/"

print(base)
print(target_apt_repository)

# Working repo
if repo_exist(target_apt_repository, base):
    depends_list.append(target_apt_repository)
else:
    print("WARNING: branch repo '%s' does not exist, please ignore if this is a new branch" % target_apt_repository)

# Extension repo
if is_extension(target_apt_repository):
    base_extensions = extension_get_repos(target_apt_repository)
    print(base_extensions)
    for base_extension in base_extensions:
        if repo_exist(base_extension, base):
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
        if is_extension(_depend):
            base_extensions = extension_get_repos(_depend)
            print(base_extensions)
            for base_extension in base_extensions:
                if repo_exist(base_extension, base):
                    depends_list.append(base_extension)
                else:
                    print("ERROR: Extension repo '%s' do not exist" % base_extension)
                    sys.exit(1)
        if repo_exist(_depend, base):
            depends_list.append(_depend)
        else:
            print("ERROR: ubports.depends repo '%s' do not exist" % _depend)
            sys.exit(1)

print("Branches %s " % depends_list)

deb_sources_list = []
for _depend in depends_list:
    deb_sources_list.append(DEB_SOURCE_TEMPLATE % (base, _depend))

if enable_backports():
    deb_sources_list.append(BACKPORTS.format(get_archive()))

deb_sources = ",".join(deb_sources_list)

with open("ubports.repos_extra", "w") as f:
    f.write(deb_sources)
