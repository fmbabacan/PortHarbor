cask "portharbor" do
  version "1.0.4"
  sha256 arm: "e1b5c7e6ffee2701a4caaaa2566cc5496c9b914983495e60418b0b56e3aefee8", intel: "4ac649ff94f187e6a1d70e1fbf6ddc033da4177452f6b889d733cbe916b4aed1"

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
