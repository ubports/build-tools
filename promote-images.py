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

# I promote images!

import argparse
import datetime
import json
import os
import subprocess
import time

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
            ch = channel.split("=>")
            ch = [x.strip() for x in ch]
            channels.append(ch)
    else:
        die("Channel list %s not found" % clist)

    return channels

def getMatchingDevices(source, dest):
    dev = []
    for device in source:
        if device in dest:
            dev.append(device)
        else:
            print("Did not find destination channel for {}".format(device))

    for device in dest:
        if not device in source:
            print("Did not find source channel for {}".format(device))

    print(dev)
    return dev


def getDevicesForAll(channels):
    ret_channels = {}
    index = requests.get("https://system-image.ubports.com/channels.json").json()

    for channel in channels:
        last = False

        for chan in channel:
            if not chan in index:
                print("Did not find channel {}".format(channel))
                continue

            index_dev = index[chan]["devices"]
            ret_channels[chan] = list(index_dev.keys())

    return ret_channels


def getLastTag(channel):
    tag = None
    index = requests.get("https://system-image.ubports.com/ubports-touch/16.04/%s/bacon/index.json" % channel)
    if not index:
        return tag
    index = index.json()
    if len(index["images"]) > 1:
        raw_tag = index["images"][-2]["version_detail"].split(",")
        for detail in raw_tag:
            if detail.startswith("tag="):
                tag = detail.split("=")[1]
                break
    return tag


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
        exit()

    return blocker


parser = argparse.ArgumentParser(description='I promote images!')
parser.add_argument("copy_images_script", metavar="COPY-IMAGES-SCRIPT")
parser.add_argument("channel_list", metavar="CHANNEL-LIST")
parser.add_argument("-r", "--version", type=int)
parser.add_argument("-o", "--offset", type=int, help="Version offset")
parser.add_argument("-k", "--keep-version", action="store_true",
                    help="Keep the original version number")
parser.add_argument("-p", "--phased-percentage", type=int,
                    help="Set the phased percentage for the copied image",
                    default=100)
parser.add_argument("-t", "--tag", type=str,
                    help="Set a version tag on the new image")
parser.add_argument("-w", "--tag-weekly", action="store_true",
                    help="Set weekly tag")
parser.add_argument("-e", "--tag-ota", type=int,
                    help="Set ota tag")
parser.add_argument("--verbose", "-v", action="count", default=0)
parser.add_argument("--dry", "-d", help="Do a dry run", action="store_true")
parser.add_argument("-l", "--label", type=str, action="append",
                    help="Github label blocker to check for (default: 'critical (rc),critical (devel)')")
parser.add_argument("-q", "--push-notify", action="store_true", default=False)

args = parser.parse_args()

# Workaround for python bug 16399
if not args.label:
    args.label = ["critical (devel)", "critical (rc)"]


for lab in args.label:
    checkGithubLabel(lab)

print("No Github blocker, Promoting images")

if not os.path.isfile(args.copy_images_script):
    print("%s is not a file" % args.copy_images_script)
    if not args.dry:
        exit()

channels = getChannelList(args.channel_list)
devices_in_channels = getDevicesForAll(channels)

new_tag = None

if args.tag_weekly:
    new_tag = time.strftime("%Y-W%V")
    last_tag = getLastTag("rc")
    print("Last image tag was %s" % last_tag)
    if last_tag:
        if last_tag == new_tag:
            new_tag = "%s/2" % new_tag
        elif "/" in last_tag:
            ltag = last_tag.split("/")
            if ltag[0] == new_tag:
                new_tag = "%s/%i" % (new_tag, int(ltag[1])+1)
    print("Setting tag to %s" % new_tag)

if args.tag_ota:
    last_tag = getLastTag("stable")
    if last_tag:
        if "OTA-" in last_tag:
            last_ota_v = last_tag.split("-")[1]
            print("last ota version was %s" % last_ota_v)
            if int(args.tag_ota) <= int(last_ota_v):
                print("Ota version cannot be lower or equal to last version! %s =< %s"
                      % (args.tag_ota, last_ota_v))
                exit()
    new_tag = "OTA-%s" % args.tag_ota

copyImageArgs = [args.copy_images_script]

copyImageArgs2 = []

if args.push_notify:
    copyImageArgs2 += ["-q"]
if args.version:
    copyImageArgs2 += ["-r", str(args.version)]
if args.offset:
    copyImageArgs2 += ["-o", str(args.offset)]
if args.keep_version:
    copyImageArgs2 += ["-k"]
if args.phased_percentage and args.phased_percentage != 100:
    copyImageArgs2 += ["-p", str(args.phased_percentage)]
if new_tag:
    copyImageArgs2 += ["-t", str(new_tag)]
else:
    if args.tag:
        copyImageArgs2 += ["-t", str(args.tag)]
if args.verbose and args.verbose != 0:
    a = "-"
    for x in range(0, args.verbose):
        a += "v"
    copyImageArgs2 += [a]

for channel in channels:
    source_channel = channel[0]
    destination_channel = channel[1]
    if not source_channel in devices_in_channels:
        print("Didn't find any source channel named {}".format(source_channel))
    if not destination_channel in devices_in_channels:
        print("Didn't find any destination channel named {}".format(destination_channel))

    src_devices = devices_in_channels[source_channel]
    dest_devices = devices_in_channels[destination_channel]

    devices = getMatchingDevices(src_devices, dest_devices)

    print("Promoting channel {} from {}".format(destination_channel, source_channel))

    for device in devices:
        cmd = copyImageArgs + [source_channel, destination_channel, device] + copyImageArgs2
        print("Promoting %s to %s from %s" % (device, destination_channel, source_channel))
        if args.dry:
            print(cmd)
        else:
            result = subprocess.run(cmd)
            if result.returncode != 0:
                print("Error during execution of copy-image, result might be broken!")
                sys.exit(result.returncode)
