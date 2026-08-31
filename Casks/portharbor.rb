cask "portharbor" do
  version "1.0.2"
  sha256 arm: "8bb88917ac2bdcd6eb23bf5b72731db36032c680b9c2c579e1ef9a3ff4bef432", intel: "b5bbaa4cba89df612b2e56441c6202bd4500d1ec25936e38f6759933da7f024e"

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
