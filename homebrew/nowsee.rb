cask "nowsee" do
  version "0.2.0"
  sha256 "5318ed2276945da6679ee53ff9a45bfca2d6397ce463ba471ac4e89c64ed5342"

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
    Nowsee is signed but not notarized. If macOS blocks the first launch, open
    /Applications in Finder, Control-click Nowsee, choose Open, then confirm Open.

    On first launch macOS asks for permission to record system audio. Nowsee cannot
    draw anything without it. Nothing is recorded to disk and nothing leaves the Mac.
  EOS
end
