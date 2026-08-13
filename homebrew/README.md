# Homebrew cask

`nowsee.rb` is the cask definition. It is kept here so it stays in step with the app, and copied
into the tap repository on release.

The sha256 in this file is a placeholder until the first `make release` fills it in.

## One-time setup of the tap

Homebrew resolves `brew tap Sergio-prog/tap` to the GitHub repository `Sergio-prog/homebrew-tap`,
so the name has to be exactly that.

```sh
gh repo create homebrew-tap --public \
  --description "Homebrew casks for Sergio-prog's apps"
git clone https://github.com/Sergio-prog/homebrew-tap.git ../homebrew-tap
mkdir -p ../homebrew-tap/Casks
```

## Releasing

```sh
make release
```

That runs the checks, builds and signs the app, creates the ZIP and DMG, rewrites `version` and
`sha256` in this cask, and prints the commands needed to finish the release.

Then commit the tap. Verify before announcing it:

```sh
brew untap Sergio-prog/tap 2>/dev/null
brew tap Sergio-prog/tap
brew trust --cask Sergio-prog/tap/nowsee
brew audit --cask --online Sergio-prog/tap/nowsee
brew install --cask --no-quarantine nowsee
```

Bumping a version means editing `CFBundleShortVersionString` in `Sources/Nowsee/Info.plist` — the
Makefile reads it from there, so it is the single source of truth.

## Why `--no-quarantine`

The app is signed with a self-signed certificate, not notarized. Homebrew quarantines downloaded
casks, and Gatekeeper then refuses to launch an app it cannot verify. `--no-quarantine` skips that
attribute; opening the app once from Finder with right-click → Open is the equivalent manual step.

Notarizing removes the need for either, and needs a paid Apple Developer account. It is on the
[roadmap](../ROADMAP.md).

## The official homebrew-cask repository

Third-party taps cannot mark themselves as globally trusted. To remove the per-user trust step,
Nowsee must be accepted into `Homebrew/homebrew-cask`. Before submitting it, sign the app with an
Apple Developer ID and notarize it so installation no longer needs `--no-quarantine`; official
casks cannot require users to bypass Gatekeeper.
