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
  version "1.4.0"
  sha256 "f8c1b9ba3556f714eb92b9c9fe693783c9dbdcae8b087e3637690bad822bc2eb"

  url "https://github.com/whispaste/whispaste/releases/download/v#{version}/WhisPaste-#{version}-macos-arm64.zip",
      verified: "github.com/whispaste/whispaste/"
  name "WhisPaste"
  desc "Cross-platform dictation — hotkey, speak, paste anywhere"
  homepage "https://whispaste.de/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :monterey"
  depends_on arch: :arm64

  app "WhisPaste.app"

  # Bundle-ID seit v1.4.0 de.whispaste.direct (de.whispaste.app gehört seitdem
  # allein dem Mac-App-Store-Build; davor seit v1.2.58 auch dem DMG, zuvor
  # com.whispaste.whispaste). Alte Pfade bleiben gelistet, da die App-seitige
  # Migration bestehende Nutzerdaten kopiert statt verschiebt — sie können
  # also unter der alten Identität liegen bleiben, bis ein Zap sie entfernt.
  zap trash: [
    "~/Library/Application Support/de.whispaste.direct",
    "~/Library/Caches/de.whispaste.direct",
    "~/Library/Preferences/de.whispaste.direct.plist",
    "~/Library/HTTPStorages/de.whispaste.direct",
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
