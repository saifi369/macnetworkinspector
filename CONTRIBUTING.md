# Contributing

Thanks for your interest in Net Inspector! Bug reports, feature requests and
pull requests are all welcome.

## Reporting bugs

Open an issue and include:

- your macOS version (`sw_vers`),
- what you expected and what happened instead,
- if the numbers look wrong, the output of
  `nettop -P -d -x -n -L 3 -J bytes_in,bytes_out -t external` so we can compare.

## Development

```bash
git clone https://github.com/saifi369/macnetworkinspector.git
cd macnetworkinspector
./build.sh --run     # builds build/Net Inspector.app and launches it
```

The project is a plain Swift package, so `swift build` and any editor work;
`open Package.swift` opens it in Xcode.

Layout:

| Path | Purpose |
| --- | --- |
| `Sources/NetInspector/NetTopMonitor.swift` | Runs `nettop`, parses its output, publishes per-app speeds |
| `Sources/NetInspector/ProcessResolver.swift` | pid → responsible app, name and icon |
| `Sources/NetInspector/ProcessKiller.swift` | Quit / force-kill, with admin fallback |
| `Sources/NetInspector/Views/` | SwiftUI menu bar label and popover |
| `Sources/CPtySpawn/` | Tiny C helper that spawns `nettop` on a controlling pty |
| `scripts/make-icon.swift` | Renders the app icon at build time |

## Pull requests

- Keep changes focused; one topic per PR.
- The build must stay warning-free (`swift build -c release`).
- Follow the existing style: 4-space indentation, `// MARK:` sections,
  no force-unwraps outside of obviously-safe literals.
- Describe how you tested the change (which apps, what traffic).

## License

By contributing you agree that your contributions are licensed under the
MIT License that covers the project.
