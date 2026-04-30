cask "openquack" do
  version "2.0.0-alpha.6"
  # Set per-release by scripts/make_dmg.sh — paste the printed value in
  # before each tag is pushed. `:no_check` is the placeholder while no
  # release has been tagged yet.
  sha256 "540a91ff0b58187d323186cd7a4c8f4293de23003326308bb6ef35df7a8e5ec5"

  url "https://github.com/larryxiao/openquack/releases/download/v#{version}/OpenQuack-#{version}.dmg"
  name "OpenQuack"
  desc "Voice dictation for macOS that runs entirely on your Mac"
  homepage "https://github.com/larryxiao/openquack"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "OpenQuack.app"

  zap trash: [
    "~/Library/Application Support/OpenQuack",
    "~/Library/Preferences/org.openquack.OpenQuack.plist",
    "~/Library/Saved Application State/org.openquack.OpenQuack.savedState",
    "~/.cache/openquack-bench",
  ]
end
