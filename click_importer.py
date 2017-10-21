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

import argparse, requests, tqdm, os, configparser

class Ctrl(object):
    def __init__(self, path):
        self.path = path
        self.file = os.path.join(path, 'apps_ctrl.ini')
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
        with open(self.file, 'w') as f:
            self.config.write(f)

    def read(self):
        config = configparser.ConfigParser()
        if os.path.exists(self.file):
            config.read(self.file)
        if not "apps" in config:
            config["apps"] = {}
        self.config = config


def get_app_info(app):
    r = requests.get(APPS_API+app)
    if not r.status_code == 200:
        return False
    return r.json()["data"]

def download_app(url, dest):
    fileName = os.path.basename(url)
    request = requests.get(url, stream=True)
    if not os.path.exists(dest):
        os.makedirs(dest)
    if os.path.isfile("%s/%s.tmp" % (dest, fileName)):
        os.remove("%s/%s.tmp" % (dest, fileName))
    with open("%s/%s.tmp" % (dest, fileName), "wb") as handle:
        total_length = int(request.headers.get('content-length'))
        for data in tqdm.tqdm(request.iter_content(chunk_size=1024), total=total_length/1024, leave=True, unit='B', unit_scale=True):
            handle.write(data)
    os.rename("%s/%s.tmp" % (dest, fileName), "%s/%s" % (dest, fileName))
    return "%s/%s" % (dest, fileName)

DEFAULT_DIR="clicks"
BASE_API="http://openstore.ubports.com/api/"
APPS_API=BASE_API+"apps/"
DOWNLOAD_API=BASE_API+"download/"

parser = argparse.ArgumentParser(description='I import clicks from the openstore')
parser.add_argument("--dir", "-o", help="output directory", type=str)
parser.add_argument("--dry", "-n", help="do a dry run", action='store_true')
group = parser.add_mutually_exclusive_group(required=True)
group.add_argument("--file", "-f", help="file with list of apps to import", type=str)
group.add_argument("--apps", "-a", nargs="+", help="apps to import")

args = parser.parse_args()

output_dir = DEFAULT_DIR;
apps = args.apps

if args.dir:
    if not os.path.exists(args.dir):
        print("Directory %s do not exist" % args.dir)
        exit()
    output_dir = args.dir

if args.file:
    if os.path.isfile(args.file):
        apps = []
        with open(args.file) as f:
            apps = f.readlines()
        apps = [x.strip() for x in apps]

ctrl = Ctrl(output_dir)

for app in apps:
    app_info = get_app_info(app)
    if app_info:
        if ctrl.isNew(app_info["id"], app_info["revision"]):
            print("New version of %s" % app_info["name"])
        else:
            print("No new version of %s" % app_info["name"])
            continue
        if args.dry:
            print("downloading %s" % app_info["name"])
        else:
            download_app(app_info["download"], output_dir)
        ctrl.update(app_info["id"], app_info["revision"])
    else:
        print("Could find fine app %s... ignoring" % app)
