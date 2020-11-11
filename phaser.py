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

# I phase images!

import argparse
import datetime
import json
import os
import subprocess
import time
import sys

import requests

def die(m):
    print(m)
    exit()

def getChannelList(clist):
    channels = []
    if os.path.isfile(clist):
        with open(clist) as f:
            _channels = f.readlines()
        for channel in _channels:
            ch = channel.split("=>")[1].strip()
            channels.append(ch)
    else:
        die("Channel list %s not found" % clist)

    return channels

def getDevicesForAll(channels):
    ret_channels = {}
    index = requests.get("https://system-image.ubports.com/channels.json").json()

    for channel in channels:
        if not channel in index:
            print("Did not find channel {}".format(channel))
            continue

        index_dev = index[channel]["devices"]
        ret_channels[channel] = list(index_dev.keys())

    return ret_channels

def getDeviceIndex(channel, device):
    index = requests.get("https://system-image.ubports.com/{}/{}/index.json".format(channel, device))
    if not index:
        return False
    return index.json()

def getPhaseVersionForTag(index, tag):
    for image in index["images"]:
        raw_tag = image["version_detail"].split(",")
        for detail in raw_tag:
            if detail.startswith("tag="):
                image_tag = detail.split("=")[1]
                break
        if image_tag == tag:
            if "phased-percentage" in image:
                return {
                    "phase": int(image["phased-percentage"]),
                    "version": int(image["version"])
                }
    return False

def checkGithubLabel(label):
    issuesPayload = {"labels": label, "state": "open"}
    issues = requests.get("https://api.github.com/repos/ubports/ubuntu-touch/issues", params=issuesPayload)
    issuesJson = issues.json()

    # Set blocker to normally True, and only if == 0 set to False
    blocker = True
    if len(issuesJson) == 0:
        blocker = False

    if blocker:
        print("!! Github label blocker !!\n")
        print("Following issues is blocking:")
        for iss in issuesJson:
            print("- %s (%s)" % (iss["title"], iss["html_url"]))

    return blocker


parser = argparse.ArgumentParser(description='I promote images!')
parser.add_argument("set_phase_script", metavar="SET-PHASE-SCRIPT")
parser.add_argument("channel_list", metavar="CHANNEL-LIST")
parser.add_argument("-p", "--phased-percentage", type=int,
                    help="Set the phased percentage for the copied image")
parser.add_argument("-b", "--phased-bump", type=int,
                    help="Bump phase by")
parser.add_argument("-t", "--tag", type=str,
                    help="The tag to phase")
parser.add_argument("--verbose", "-v", action="count", default=0)
parser.add_argument("--dry", "-d", help="Do a dry run", action="store_true")
parser.add_argument("-l", "--label", type=str, action="append",
                    help="Github label blocker to check for (default: 'critical (rc),critical (devel)')")

args = parser.parse_args()

# Workaround for python bug 16399
if not args.label:
    args.label = ["critical (devel)", "critical (rc)"]

if not args.phased_bump and not args.phased_percentage:
    die("Phased-bump or Phased-percentage is not set, one of them is requied")

if args.phased_bump and args.phased_percentage:
    die("Both Phased-bump or Phased-percentage are set, only one of them is requied")

if not args.tag:
    die("Missing tag argument")

blocker = False
for lab in args.label:
    if checkGithubLabel(lab):
        blocker = True

if blocker:
    print("has Gitbug blocker, phasing images to 1")
else:
    print("No Github blocker, Phasing images")

if not os.path.isfile(args.set_phase_script):
    print("%s is not a file" % args.set_phase_script)
    if not args.dry:
        exit()

channels = getChannelList(args.channel_list)
devices_in_channels = getDevicesForAll(channels)


copyImageArgs = [args.set_phase_script]

copyImageArgs2 = []

if args.verbose and args.verbose != 0:
    a = "-"
    for x in range(0, args.verbose):
        a += "v"
    copyImageArgs2 += [a]

for channel, devices in devices_in_channels.items():
    for device in devices:
        index = getDeviceIndex(channel, device)
        if not index:
            print("Did not find index for {} in {}".format(device, channel))
            continue
        phase_ver = getPhaseVersionForTag(index, args.tag)
        if not phase_ver:
            print("Did not find phase for {} in {}".format(device, channel))
            continue

        phase = phase_ver["phase"]
        version = phase_ver["version"]

        if phase == 100:
            print("{} in {} is already at 100".format(device, channel))
            continue

        if not phase:
            print("No phase for {} in {}".format(device, channel))
            continue

        if blocker:
            print("emergency: Setting phase to 1 as we got a github blocker")
            to_phase = 1
        else:
            if (args.phased_percentage):
                print("Setting phase to {}".format(args.phased_percentage))
                to_phase = int(args.phased_percentage)
            else:
                print("Bumping phase by {}".format(args.phased_bump))
                to_phase = phase + args.phased_bump
            if to_phase > 100:
                to_phase = 100

        cmd = copyImageArgs + [channel, device, str(version), str(to_phase)] + copyImageArgs2
        print("phasing version {} for {} in {} from {} to {}".format(version, device, channel, phase, to_phase))
        if args.dry:
            print(cmd)
        else:
            result = subprocess.run(cmd)
            if result.returncode != 0:
                print("Error during execution of copy-image, result might be broken!")
                sys.exit(result.returncode)
