cask "torli-stats" do
  version "1.12.6"
  sha256 "aac9d05b9c55d69931b55c203dc30bacdbbec96dc8c8c6de734882154a3b2f74"

  url "https://github.com/JamesLi-dev/torli-stats/releases/download/v#{version}/TorliStats-#{version}-macos-arm64.zip"
  name "Torli Stats"
  desc "Community edition system monitor for the macOS menu bar"
  homepage "https://github.com/JamesLi-dev/torli-stats"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "TorliStats.app"

  caveats <<~EOS
    This is the community edition, not Pro. Both editions use the same app
    identity and installation path, so do not install this over Pro unless you
    intend to replace it. They cannot run as separate identities.

    This app is ad-hoc signed and is not notarized by Apple; macOS may block
    its first launch or request permissions again after an update. The optional
    sensor helper is managed separately by the app and is not removed by
    uninstalling this cask.
  EOS
end
