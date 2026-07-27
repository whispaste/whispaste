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
  version "1.2.58"
  sha256 "fd5b8adf852d799372ea78e2a99b07ba1e5db707f81ce6e70fa73443caa5e66b"

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

  app "whispaste.app"

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
