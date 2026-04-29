cask "openquack" do
  version "2.0.0-alpha.2"
  # Set per-release by scripts/make_dmg.sh — paste the printed value in
  # before each tag is pushed. `:no_check` is the placeholder while no
  # release has been tagged yet.
  sha256 "a5890f1e29aae099abd691db06ed890d0975079fcae03690c50bc49a58fd786a"

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
