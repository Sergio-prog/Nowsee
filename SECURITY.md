# Security

## Reporting a vulnerability

Report privately through [GitHub Security Advisories](https://github.com/Sergio-prog/Nowsee/security/advisories/new).
Please do not open a public issue for a vulnerability.

Expect a first reply within a week. If a fix is needed it ships in the next release, and the
advisory is published once it is out.

## What is worth reporting

Nowsee holds a Core Audio process tap on the system output mix — the most sensitive thing it
touches. Anything that breaks these properties is in scope:

- Audio leaving the process. It is turned into FFT magnitudes in memory and drawn; nothing is
  written to disk and the app makes no network requests.
- The audio permission being obtained or retained in a way the user did not grant.
- Another process reading Nowsee's capture buffers or aggregate device.
- Code execution through a crafted settings value, palette import, or share link.

The studio at `/studio/` runs entirely in the browser tab. Audio from the microphone, a file, or a
shared tab never leaves it, and settings live in `localStorage`. A path that uploads any of it is
in scope.

## Not vulnerabilities

- **Gatekeeper refusing the first launch.** The app is signed but not notarized, which needs a paid
  Apple Developer account. See the [roadmap](ROADMAP.md).
- **`--no-quarantine` in the Homebrew instructions.** Same cause, and the documented alternative is
  opening the app once from Finder.
- The app being able to see audio the user is playing. That is the entire feature.

## Supported versions

The latest release only.
