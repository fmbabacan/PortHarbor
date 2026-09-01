cask "portharbor" do
  version "1.0.3"
  sha256 arm: "3cf746a5abfbf1af8424ab8b1731f683f64e4253681583c3b91fbc2f125eba33", intel: "e3edb94605fcb0c263cc2dc9079ec02d96095920f82b8355242e28dc2b218c37"

  on_arm do
    url "https://github.com/fmbabacan/PortHarbor/releases/download/v#{version}/PortHarbor-#{version}-arm64.zip"
  end

  on_intel do
    url "https://github.com/fmbabacan/PortHarbor/releases/download/v#{version}/PortHarbor-#{version}-x86_64.zip"
  end

  name "PortHarbor"
  desc "Native macOS service radar"
  homepage "https://github.com/fmbabacan/PortHarbor"
  depends_on macos: ">= :sequoia"
  app "PortHarbor.app"
end
