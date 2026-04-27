cask "openquack" do
  version "2.0.0-alpha.1"
  # Placeholder; will be set per-release by scripts/make_dmg.sh and pasted in
  # before each tag is pushed. Use `:no_check` until v0 is actually published.
  sha256 :no_check

  url "https://github.com/OpenQuack/openquack/releases/download/v#{version}/OpenQuack-#{version}.dmg"
  name "OpenQuack"
  desc "Privacy-first local AI agent interface, accessed via voice"
  homepage "https://github.com/OpenQuack/openquack"

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
