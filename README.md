# Net Inspector

[![Build](https://github.com/saifi369/macnetworkinspector/actions/workflows/build.yml/badge.svg)](https://github.com/saifi369/macnetworkinspector/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey)

A tiny macOS menu bar utility that shows **which app is using how much of your
internet connection right now**, and lets you quit or force-kill the culprit
with one click.

Your speed-test widget says you are pulling 25 MB/s, but *what* is doing it?
Net Inspector answers that in one click.

<p align="center">
  <img src="docs/screenshots/menubar-dark.png" width="313" alt="Menu bar showing live download and upload speed">
</p>
<p align="center">
  <img src="docs/screenshots/popover-dark.png" width="452" alt="Per-app breakdown with Quit and force-kill buttons">
</p>

<sub>Screenshots are rendered from demo data (`./build.sh --screenshots`); light mode looks like
<a href="docs/screenshots/popover-light.png">this</a>.</sub>

## Features

- Live download / upload speed in the menu bar.
- Click it for a per-app breakdown, busiest app first, with app icons and a
  usage bar.
- Helper processes are grouped under their app (Chrome/Brave/Safari helpers,
  XPC services, CLI tools launched from Terminal…). Expand a row to see them
  and kill them individually.
- **Quit** asks the app to quit nicely. **⛔** force-kills (asks for
  confirmation). Root-owned daemons prompt for your admin password.
- Settings (gear): MB/s or Mbps, what to show in the menu bar, refresh rate,
  Launch at Login.

No root, no kernel extension, no network filter, no telemetry: it reads the
per-process counters from the built-in `nettop` tool, the same data Activity
Monitor uses. It never touches your traffic, only the byte counts.

## Install

Requires macOS 14 Sonoma or newer and Xcode (or the Command Line Tools) to build.

```bash
git clone https://github.com/saifi369/macnetworkinspector.git
cd macnetworkinspector
./build.sh --install    # build, copy to /Applications and launch
```

Other options:

```bash
./build.sh              # just build into build/Net Inspector.app
./build.sh --run        # build and launch from the build folder
```

The app is ad-hoc signed, so Gatekeeper will not complain about a build you
made yourself. "Launch at Login" works best once the app lives in
`/Applications`.

## How it works

- `NetTopMonitor` runs `/usr/bin/nettop -P -d -L 0 …` behind a pseudo-terminal
  (nettop block-buffers when writing to a pipe) and parses one CSV block per
  interval into bytes-per-second per pid.
- `CPtySpawn` is a small C helper that spawns nettop as a session leader with
  the pty as its controlling terminal, so nettop is hung up and exits whenever
  the app goes away, even after a hard kill.
- `ProcessResolver` maps each pid to the application responsible for it using
  `responsibility_get_pid_responsible_for_pid` from libquarantine (the same
  call Little Snitch and LuLu use), then looks up name and icon through
  `NSRunningApplication`.
- `ProcessKiller` uses `NSRunningApplication.terminate()` /
  `forceTerminate()` for apps, `SIGTERM` / `SIGKILL` for everything else, and
  falls back to an administrator prompt when permission is denied.

## Limitations

- Speeds are sampled once per interval (1 s by default), so very short bursts
  can be averaged out.
- `responsibility_get_pid_responsible_for_pid` is a private API. It has been
  stable for many macOS releases, but if Apple removes it, processes will
  simply be listed individually instead of grouped.
- Traffic from the kernel itself (e.g. some VPN tunnels) is attributed to
  `kernel_task`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and pull requests are welcome.

## License

[MIT](LICENSE) © 2026 M Saif Ullah
