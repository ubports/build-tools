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

# I import clicks from the openstore

import argparse, requests, tqdm, os, configparser, copy

class Ctrl(object):
    def __init__(self, path, arches):
        self.path = path
        self.arches = copy.copy(arches)
        self.arches.append("all")
        self.file = os.path.join(path, 'apps_ctrl.ini')
        self.read()

    def get(self, arch):
        return self.config["apps-{}".format(arch)]

    def update(self, app, rev, arch):
        self.config["apps-{}".format(arch)][app] = str(rev)
        self.write()

    def isNew(self, app, rev, arch):
        if not app in self.get(arch):
            return True
        if int(self.get(arch)[app]) < rev:
            return True
        return False

    def write(self):
        with open(self.file, 'w') as f:
            self.config.write(f)

    def read(self):
        config = configparser.ConfigParser()
        if os.path.exists(self.file):
            config.read(self.file)

        if "apps" in config:
            config["apps-armhf"] = config["apps"]
            del config["apps"]

        for arch in self.arches:
            if not "apps-{}".format(arch) in config:
                config["apps-{}".format(arch)] = {}
        self.config = config


def get_app_info(app):
    r = requests.get(APPS_API+app)
    if not r.status_code == 200:
        return False
    return r.json()["data"]

def download_app(url, id, arch, dest):
    fileName = "%s_%s.click" % (id, arch)
    request = requests.get(url, stream=True)
    try:
        total_length = int(request.headers.get('content-length'))
    except Exception as e:
        print("failed to download")
        return
    if not os.path.exists(dest):
        os.makedirs(dest)
    if os.path.isfile("%s/%s.tmp" % (dest, fileName)):
        os.remove("%s/%s.tmp" % (dest, fileName))
    with open("%s/%s.tmp" % (dest, fileName), "wb") as handle:
        for data in tqdm.tqdm(request.iter_content(chunk_size=1024), total=total_length/1024, leave=True, unit='B', unit_scale=True):
            handle.write(data)
    os.rename("%s/%s.tmp" % (dest, fileName), "%s/%s" % (dest, fileName))
    return "%s/%s" % (dest, fileName)

def check_and_download(ctrl, app_info, output_dir, download_found, args):
    arch = download_found["architecture"]
    channel = download_found["channel"]
    if ctrl.isNew(app_info["id"], download_found["revision"], arch):
        print("New version of %s (%s)" % (app_info["name"], arch))
    else:
        print("No new version of %s (%s)" % (app_info["name"], arch))
        return
    if args.dry:
        print("downloading %s (%s)" % (app_info["name"], arch))
    else:
        download_app(download_found["download_url"], app_info["id"],
                    arch, output_dir)
    ctrl.update(app_info["id"], download_found["revision"], arch)

def find_download(downloads, channel, arch):
    download_found = False
    for download in downloads:
        if download["channel"] == channel and download["architecture"] == arch:
            download_found = download

    return download_found

def find_downloads(apps, channel, arches, output_dir, args):
    ctrl = Ctrl(output_dir, arches)
    for app in apps:
        app_info = get_app_info(app)
        if app_info:
            if app_info["architecture"] == "all":
                down = find_download(app_info["downloads"], channel, "all")
                check_and_download(ctrl, app_info, output_dir, down, args)
            else:
                for arch in arches:
                    if not arch in app_info["architectures"]:
                        print("Could not find %s in channel %s for arch %s" % (app_info["name"], channel, arch))
                        continue
                    down = find_download(app_info["downloads"], channel, arch)
                    check_and_download(ctrl, app_info, output_dir, down, args)
        else:
            print("Could find fined app %s... ignoring" % app)


DEFAULT_DIR="clicks"
BASE_API="http://open-store.io/api/v4/"
APPS_API=BASE_API+"apps/"

parser = argparse.ArgumentParser(description='I import clicks from the openstore')
parser.add_argument("--dir", "-o", help="output directory", type=str)
parser.add_argument("--channel", "-c", help="channel to download from (default xenial)", type=str)
parser.add_argument("--dry", "-n", help="do a dry run", action='store_true')
group = parser.add_mutually_exclusive_group(required=True)
group.add_argument("--file", "-f", help="file with list of apps to import", type=str)
group.add_argument("--apps", "-a", nargs="+", help="apps to import")

args = parser.parse_args()

output_dir = DEFAULT_DIR
channel = "xenial"
arches = ["arm64", "armhf"]
apps = args.apps

if args.channel:
    channel = args.channel

if args.dir:
    if not os.path.exists(args.dir):
        print("Directory %s do not exist" % args.dir)
        exit()
    output_dir = args.dir

if not os.path.exists(output_dir):
    os.mkdir(output_dir)

if args.file:
    if os.path.isfile(args.file):
        apps = []
        with open(args.file) as f:
            apps = f.readlines()
        apps = [x.strip() for x in apps]

find_downloads(apps, channel, arches, output_dir, args)
