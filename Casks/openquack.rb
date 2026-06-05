cask "openquack" do
  version "2.0.0-alpha.18"
  # Set per-release by scripts/make_dmg.sh — paste the printed value in
  # before each tag is pushed. `:no_check` is the placeholder while no
  # release has been tagged yet.
  sha256 "e1ef5cd027ee697f77ee1837c9967f76f8a446fc765c91b8eb5b8299ed5c4c2a"

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
