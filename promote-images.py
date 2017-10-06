#!/usr/bin/python3

# I promote images!

import argparse, subprocess, os, requests


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
parser.add_argument("source_channel", metavar="SOURCE-CHANNEL")
parser.add_argument("destination_channel", metavar="DESTINATION-CHANNEL")
parser.add_argument("device_list", metavar="DEVICE-LIST")
parser.add_argument("-r", "--version", type=int)
parser.add_argument("-o", "--offset", type=int, help="Version offset")
parser.add_argument("-k", "--keep-version", action="store_true",
                    help="Keep the original version number")
parser.add_argument("-p", "--phased-percentage", type=int,
                    help="Set the phased percentage for the copied image",
                    default=100)
parser.add_argument("-t", "--tag", type=str,
                    help="Set a version tag on the new image")
parser.add_argument("--verbose", "-v", action="count", default=0)
parser.add_argument("--dry", "-d", help="Do a dry run", action="store_true")
parser.add_argument("-l", "--label", type=str, action="append",
                    help="Github label blocker to check for (default: 'critical (rc),critical (devel)')")

args = parser.parse_args()

devices = []

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

if os.path.isfile(args.device_list):
    with open(args.device_list) as f:
        devices = f.readlines()
    devices = [x.strip() for x in devices]
else:
    print("Device list %s not found" % args.device_list)
    exit()

copyImageArgs = [args.copy_images_script, args.source_channel, args.destination_channel]

copyImageArgs2 = []

if args.version:
    copyImageArgs2 += ["-r", str(args.version)]
if args.offset:
    copyImageArgs2 += ["-o", str(args.offset)]
if args.keep_version:
    copyImageArgs2 += ["-k"]
if args.phased_percentage and args.phased_percentage != 100:
    copyImageArgs2 += ["-p", str(args.phased_percentage)]
if args.tag:
    copyImageArgs2 += ["-t", str(args.tag)]
if args.verbose and args.verbose != 0:
    a="-"
    for x in range(0, args.verbose):
        a+="v"
    copyImageArgs2 += [a]

for device in devices:
    cmd = copyImageArgs + [device] + copyImageArgs2
    print("Promoting %s to %s from %s" % (device, args.destination_channel, args.source_channel))
    if args.dry:
        print(cmd)
    else:
        subprocess.run(cmd, check=True)
