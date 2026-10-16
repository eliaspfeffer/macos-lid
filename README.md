# macOS lid brightness

The original `lid` shell function is backed up in `lid.zsh`, on `main` and at tag
`before-brightness`. Unrelated shell settings and credentials are excluded.

`lid` keeps its original behavior and sudo prompt. A user LaunchAgent watches
`AppleClamshellState` and `SleepDisabled` in IOKit every 250 ms:

- Sleep disabled + lid closed: save the last open-lid brightness, then set the built-in display to zero.
- Lid opened, or normal sleep mode restored: restore the saved brightness.
- Normal mode without a pending restoration: leave brightness alone.

External displays are untouched. The saved value survives watcher restarts in
`~/Library/Application Support/LidBrightness/brightness.json`; it is removed only
after restoration is confirmed. Failed operations are retried. If the service
starts with the lid already closed and no saved value, it waits for the first
opening rather than guessing the original brightness.

## Install

Run `./install.sh`. It compiles and tests the Swift helper, signs it locally,
installs it in `~/.local/bin/lid-brightness`, and starts
`~/Library/LaunchAgents/com.eliaspfeffer.lid-brightness.plist`. It starts again at
login. No changes to `.zshrc` or current power settings are needed.

## Verify

```
~/.local/bin/lid-brightness --status
~/.local/bin/lid-brightness --self-test
```

Before installing/running the watcher, `build/lid-brightness --hardware-test`
briefly sets the actual built-in panel to zero and restores it using simulated
lid states. Do not run that test alongside the watcher.

For the physical check: enable wake mode with `lid`, note the brightness, close
and reopen the lid, and check it returns to that value. Repeat at another
brightness. In normal mode, the Mac should still sleep as before.

Logs: `~/Library/Logs/lid-brightness.log` (errors and restoration events only).
Brightness API follows [nriley/brightness](https://github.com/nriley/brightness/blob/master/brightness.c).
DisplayServices is a private macOS API and should be rechecked after major OS upgrades.

## Remove

Open the lid first and allow the saved brightness to restore. Then run:

```
launchctl bootout "gui/$(id -u)/com.eliaspfeffer.lid-brightness"
rm ~/Library/LaunchAgents/com.eliaspfeffer.lid-brightness.plist
rm ~/.local/bin/lid-brightness
```

The `lid` function and sleep settings remain unchanged.
