# Debugging yabai signals in Xcode

CielBar uses `SIGUSR1` and `SIGUSR2` to receive yabai events. By default,
LLDB stops an Xcode-launched process when either signal arrives.

The app then looks frozen and macOS may show the spinning cursor. Check the
Debug console for a stop reason like this:

```text
stop reason = signal SIGUSR2
```

Run these commands in Xcode's Debug console at the start of each debug session:

```lldb
process handle SIGUSR1 -s false -n false -p true
process handle SIGUSR2 -s false -n false -p true
continue
```

`SIGUSR1` reports general provider changes. `SIGUSR2` reports focus changes.
The commands tell LLDB to pass both signals to CielBar without stopping or
printing a notification.

To apply this configuration automatically, put the first two commands in
`~/.lldbinit-Xcode`. If Xcode does not load that file, use `~/.lldbinit`.
