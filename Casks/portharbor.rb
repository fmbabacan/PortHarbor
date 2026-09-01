cask "portharbor" do
  version "1.1.0"
  sha256 arm: "ff62e32113093ed96370d769e8eebfd644be90beac11f75896f519ab09fe3f9f", intel: "612e3d25e12d9d2c9b21a2fc4df81b4e2f58f48a072de432dc419ac0207defbb"

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
