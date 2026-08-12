cask "nowsee" do
  version "0.1.0"
  sha256 "aacc2d5639f61c1131c0955710f0cd6a33d786fbf5257283be5505e61069283f"

  url "https://github.com/Sergio-prog/Nowsee/releases/download/v#{version}/Nowsee-#{version}.zip",
      verified: "github.com/Sergio-prog/Nowsee/"
  name "Nowsee"
  desc "Live visualizer for system audio, in the menu bar and in a window"
  homepage "https://nowsee.serhiifotex.dev/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia

  app "Nowsee.app"

  uninstall quit: "sh.nowsee.Nowsee"

  zap trash: [
    "~/Library/Logs/nowsee.log",
    "~/Library/Preferences/sh.nowsee.Nowsee.plist",
  ]

  caveats <<~EOS
    Nowsee is signed but not notarized, so Gatekeeper will refuse the first launch.
    Either install with --no-quarantine:

      brew install --cask --no-quarantine nowsee

    or open it once from Finder with right-click -> Open.

    On first launch macOS asks for permission to record system audio. Nowsee cannot
    draw anything without it. Nothing is recorded to disk and nothing leaves the Mac.
  EOS
end
