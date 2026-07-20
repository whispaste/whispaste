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
  version "1.2.52"
  sha256 "eb241f2771955b562612a8aa749a5b15be3443018ddb551823f35a63be5dc866"

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

  # Hinweis: Bundle-ID derzeit com.whispaste.whispaste. Nach Migration auf
  # de.whispaste.app diese Pfade anpassen.
  zap trash: [
    "~/Library/Application Support/com.whispaste.whispaste",
    "~/Library/Caches/com.whispaste.whispaste",
    "~/Library/Preferences/com.whispaste.whispaste.plist",
    "~/Library/HTTPStorages/com.whispaste.whispaste",
  ]
end
