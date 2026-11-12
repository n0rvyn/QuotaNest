cask "quotanest" do
  version "0.1.2"
  sha256 "a19ebc94b2aaa9218ac093c719bb18b951fe0f68774fe4f7e3e70d903c2a74ab"

  url "https://github.com/n0rvyn/QuotaNest/releases/download/v#{version}/QuotaNest-#{version}-macos.zip"
  name "QuotaNest"
  desc "Menu bar monitor for AI resource and subscription quotas"
  homepage "https://github.com/n0rvyn/QuotaNest"

  depends_on macos: :sonoma

  app "QuotaNest.app"
end
