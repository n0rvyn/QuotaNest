cask "quotanest" do
  version "0.1.1"
  sha256 "4f2b0de38f77ecdb0889c8458a57e9a5765908d75ad3d735c98f82440766b53d"

  url "https://github.com/n0rvyn/QuotaNest/releases/download/v#{version}/QuotaNest-#{version}-macos.zip"
  name "QuotaNest"
  desc "Menu bar monitor for AI resource and subscription quotas"
  homepage "https://github.com/n0rvyn/QuotaNest"

  depends_on macos: ">= :sonoma"

  app "QuotaNest.app"
end
