# Homebrew Cask für WhisPaste (macOS, Apple Silicon).
#
# Live seit v1.2.75: macOS-Builds sind Developer-ID-signiert und notarisiert
# (release.yml, "Sign, notarize and staple .app"), Homebrew kann das Bundle
# ohne Gatekeeper-Quarantäne-Blockade installieren. Siehe packaging/README.md
# → "Homebrew Cask (macOS)".
#
# Veröffentlicht als eigener Tap: github.com/whispaste/homebrew-tap
#   -> diese Datei dort als Casks/whispaste.rb (manueller Sync pro Release,
#      release.yml pusht nicht automatisch ins externe Tap-Repo):
#      brew install --cask whispaste/tap/whispaste
cask "whispaste" do
  version "1.2.78"
  sha256 "e37ca4f6a26a119ab41dbcc00f4140d821b7db0b423ba34e0c16576fe2c6aacb"

  url "https://github.com/whispaste/whispaste/releases/download/v#{version}/WhisPaste-#{version}-macos-arm64.zip",
      verified: "github.com/whispaste/whispaste/"
  name "WhisPaste"
  desc "Cross-platform dictation — hotkey, speak, paste anywhere"
  homepage "https://whispaste.de/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :catalina"
  depends_on arch: :arm64

  app "WhisPaste.app"

  # Bundle-ID seit v1.2.58 de.whispaste.app (zuvor com.whispaste.whispaste).
  # Alte Pfade bleiben gelistet, da die App-seitige Migration bestehende
  # Nutzerdaten kopiert statt verschiebt — sie können also unter der alten
  # Identität liegen bleiben, bis ein Zap sie entfernt.
  zap trash: [
    "~/Library/Application Support/de.whispaste.app",
    "~/Library/Caches/de.whispaste.app",
    "~/Library/Preferences/de.whispaste.app.plist",
    "~/Library/HTTPStorages/de.whispaste.app",
    "~/Library/Application Support/com.whispaste.whispaste",
    "~/Library/Caches/com.whispaste.whispaste",
    "~/Library/Preferences/com.whispaste.whispaste.plist",
    "~/Library/HTTPStorages/com.whispaste.whispaste",
  ]
end
