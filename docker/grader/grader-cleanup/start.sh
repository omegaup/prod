#!/bin/sh

set -ex

find /var/lib/omegaup/grade/ -maxdepth 3 -mindepth 3 -type d -mtime +182 | xargs -n 128 rm -rf {} \;
find /var/lib/omegaup/submissions/ -type f -mtime +182 | xargs -n 128 rm -rf {} \;
find /var/lib/omegaup/ephemeral/ -maxdepth 1 -mindepth 1 -type d -mtime +1 | xargs -n 128 rm -rf {} \;
