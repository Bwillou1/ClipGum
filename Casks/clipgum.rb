cask "clipgum" do
  version "0.1.0-dev.55"
  sha256 "08498512c2d5df6697959946afa2bf5ad3c95ba78ea609170a1043affabc30d4"

  url "https://github.com/Bwillou1/ClipGum/releases/download/v0.1.0-dev.55/ClipGum-0.1.0-dev.55.dmg"
  name "ClipGum"
  desc "Explicit, local-only smart paste for Apple Silicon"
  homepage "https://github.com/Bwillou1/ClipGum"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "ClipGum.app"

  zap trash: [
    "~/Library/Containers/com.clipgum.ClipGum",
    "~/Library/Preferences/com.clipgum.ClipGum.plist",
    "~/Library/Saved Application State/com.clipgum.ClipGum.savedState",
  ]
  caveats do
    "Development build only: ad-hoc signed and not notarized. macOS may require explicit Open Anyway approval in System Settings > Privacy & Security."
  end
end
