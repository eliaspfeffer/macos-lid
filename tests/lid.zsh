#!/bin/zsh
# Exercise the real command without changing system power settings.
set -eu
cd "${0:A:h}/.."
source ./lid.zsh
mock_state=0
mock_fail=0
pmset() { print "SleepDisabled $mock_state"; }
sudo() {
  (( mock_fail )) && return 1
  mock_state=$3
  return 0
}
lid
[[ $mock_state == 1 ]]
lid
[[ $mock_state == 0 ]]
mock_fail=1
if lid; then
  print -u2 "FAIL: permission failure must be reported"
  exit 1
fi
[[ $mock_state == 0 ]]
print 'PASS: enable, disable, and permission failure'
