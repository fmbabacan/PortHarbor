cask "portharbor" do
  version "1.0.0"
  sha256 arm: "47159e12ed63c5df3b7490644074066431c5290d61dd22449afb2b0c3839ca21", intel: "d65d05ce42539e1b4230e16dc61c08053dc9edf3bc47d35b2835c36a539a7ecb"

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
