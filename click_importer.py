#!/usr/bin/python3

# Copyright (C) 2017 Marius Gripsgard <marius@ubports.com>
# Copyright (C) 2020 UBports Foundation
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

"""
Script to import and cache clicks from the OpenStore into a filesystem directory
"""

import argparse
import configparser
import os

import requests
import tqdm


class Ctrl(object):
    def __init__(self, path):
        self.path = path
        self.file = os.path.join(path, "apps_ctrl.ini")
        self.read()

    def get(self):
        return self.config["apps"]

    def update(self, app, rev):
        self.config["apps"][app] = str(rev)
        self.write()

    def isNew(self, app, rev):
        if not app in self.get():
            return True
        if int(self.get()[app]) < rev:
            return True
        return False

    def write(self):
        with open(self.file, "w") as f:
            self.config.write(f)

    def read(self):
        config = configparser.ConfigParser()
        if os.path.exists(self.file):
            config.read(self.file)
        if not "apps" in config:
            config["apps"] = {}
        self.config = config


def get_app_info(app, architecture):
    r = requests.get(APPS_API + app, params={"architecture": architecture})
    if not r.status_code == 200:
        return False
    return r.json()["data"]


def download_app(url, id, arch, dest, name):
    """Downloads an app using the OpenStore API

    :param url: Full URL to the app download. Redirects will be resolved.

    :id: App ID (for example, 'com.ubuntu.calculator').

    :arch: Architecture to download ('all', 'armhf', 'arm64'...).

    :dest: Working directory *and* destination directory for the file. The file
    will be downloaded into this directory with a temporary name then
    renamed.

    :name: Final filename for the downloaded app. The temporary download will
    be renamed to this.

    :returns: Full path to the downloaded file, or None if the file failed to
    download.
    """
    end_file_path = "{}/{}".format(dest, name)
    temporary_file_path = end_file_path + ".tmp"

    request = requests.get(url, stream=True)
    try:
        total_length = int(request.headers.get("content-length"))
    except Exception:
        print("failed to download")
        return
    if not os.path.exists(dest):
        os.makedirs(dest)
    if os.path.isfile(temporary_file_path):
        os.remove(temporary_file_path)
    with open(temporary_file_path, "wb") as handle:
        for data in tqdm.tqdm(
            request.iter_content(chunk_size=1024),
            total=total_length / 1024,
            leave=True,
            unit="B",
            unit_scale=True,
        ):
            handle.write(data)
    os.rename(temporary_file_path, end_file_path)
    return end_file_path


def write_click_list(list_location, clicks):
    """Creates a list of clicks to be downloaded by the rootfs builder

    :param list_location: The click list will be placed at this location.

    :param clicks: List of filenames to enter into the click list.

    As of this writing, the script responsible for parsing this list was
    https://github.com/ubports/livecd-rootfs/blob/xenial/live-build/ubuntu-touch/hooks/60-install-click.chroot
    """
    print("Writing final click list to " + list_location)

    with open(list_location, "w") as click_list:
        click_list.write("\n".join(clicks))


def click_name(app_id, version, architecture):
    """Rebuilds a click's expected filename.

    Needed because the store does not give us information about filenames in
    downloads, it is expected that the API redirects the browser
    appropriately.
    """
    return "{app_id}_{version}_{architecture}.click".format(
        app_id=app_id, version=version, architecture=architecture
    )


DEFAULT_DIR = "clicks"
BASE_API = "http://open-store.io/api/v3/"
APPS_API = BASE_API + "apps/"


parser = argparse.ArgumentParser(description="I import clicks from the openstore")
parser.add_argument("--dir", "-o", help="output directory", type=str)
parser.add_argument(
    "--channel",
    "-c",
    help="channel to download from (default=xenial)",
    type=str,
    default="xenial",
)
parser.add_argument(
    "--architecture",
    help="Architecture to download (default=armhf)",
    type=str,
    default="armhf",
)

group = parser.add_mutually_exclusive_group(required=True)
group.add_argument("--file", "-f", help="file with list of apps to import", type=str)
group.add_argument("--apps", "-a", nargs="+", help="apps to import")


args = parser.parse_args()

output_dir = DEFAULT_DIR
channel = args.channel
apps = args.apps
arch = args.architecture

if args.dir:
    if not os.path.exists(args.dir):
        print("Directory {} does not exist".format(args.dir))
        exit()
    output_dir = args.dir

if args.file:
    if os.path.isfile(args.file):
        apps = []
        with open(args.file) as f:
            apps = f.readlines()
        apps = [x.strip() for x in apps]

ctrl = Ctrl(output_dir)

click_list = []

for app in apps:
    app_info = get_app_info(app, arch)
    if app_info:
        download_found = False
        for download in app_info["downloads"]:
            if download["channel"] == channel:
                download_found = download

        app_id = app_info["id"]
        app_name = app_info["name"]
        if download_found:
            download_version = download_found["version"]
            download_architecture = download_found["architecture"]
            download_revision = download_found["revision"]
            download_file_name = click_name(
                app_id, download_version, download_architecture
            )
            download_url = download_found["download_url"]
            control_appid = "{}_{}".format(app_id, download_architecture)

            click_list.append(download_file_name)
            if ctrl.isNew(control_appid, download_revision):
                print("New version of {}".format(app_name))
            else:
                print("No new version of {}".format(app_name))
                continue
            download_app(
                download_url,
                app_id,
                download_architecture,
                output_dir,
                download_file_name,
            )
            ctrl.update(control_appid, download_revision)
        else:
            print("Could not find {} in channel {}".format(app_name, channel))
    else:
        print("Could find app {} for architecture {}... ignoring".format(app, arch))

if arch == "armhf":
    write_click_list(output_dir + "/click_list", click_list)
else:
    write_click_list(output_dir + "/click_list.{}".format(arch), click_list)
