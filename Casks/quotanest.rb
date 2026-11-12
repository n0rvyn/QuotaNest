cask "quotanest" do
  version "0.1.0"
  sha256 "c4c295fc6fe4dd5ca94d280d3e1db464410ee466e1fde25e3fc3795bd07c4b29"

  url "https://github.com/n0rvyn/QuotaNest/releases/download/v#{version}/QuotaNest-#{version}-macos.zip"
  name "QuotaNest"
  desc "Menu bar monitor for AI resource and subscription quotas"
  homepage "https://github.com/n0rvyn/QuotaNest"

  depends_on macos: ">= :sonoma"

  app "QuotaNest.app"
end
