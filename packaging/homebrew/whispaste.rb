# Homebrew Cask für WhisPaste (macOS, Apple Silicon).
#
# ⚠️ VORAUSSETZUNG: Erst veröffentlichen, wenn die macOS-Builds Developer-ID-
# signiert UND notarisiert sind. Ohne Notarization setzt Homebrew das App-Bundle
# unter Quarantäne und Gatekeeper blockt den Start — schlechte Nutzererfahrung.
# Siehe packaging/README.md → "Homebrew (macOS)".
#
# Veröffentlichung als eigener Tap: github.com/whispaste/homebrew-tap
#   -> Datei dort als Casks/whispaste.rb ablegen, dann:
#      brew install --cask whispaste/tap/whispaste
cask "whispaste" do
  version "1.2.72"
  sha256 "fc6a52a5b9c00cfa1a00d2eba84cf5a231b6554edc4959188fea39a55d76c50b"

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
