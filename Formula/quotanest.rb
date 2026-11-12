class Quotanest < Formula
  desc "Native macOS menu bar monitor for Volcengine Ark quotas"
  homepage "https://github.com/n0rvyn/QuotaNest"
  url "https://github.com/n0rvyn/QuotaNest/releases/download/v0.1.0/QuotaNest-0.1.0-source.tar.gz"
  sha256 "65518ceda4be9b323caafa6b02b224c2195e5c65bbca082ebf4e4fdc2c1c441e"
  version "0.1.0"

  depends_on xcode: ["16.0", :build]
  depends_on macos: :sonoma

  def install
    ENV["QUOTANEST_NO_PACKAGE_SANDBOX"] = "1"
    system "./scripts/build-app.sh"
    prefix.install "dist/QuotaNest.app"
    bin.install_symlink prefix/"QuotaNest.app/Contents/MacOS/QuotaNest" => "quotanest"
  end

  def caveats
    <<~EOS
      Launch QuotaNest:
        open "#{opt_prefix}/QuotaNest.app"
      Enter your Ark Access Key and Secret Key in Settings. Credentials stay in macOS Keychain.
    EOS
  end

  test do
    assert_match "QuotaNest", shell_output("#{bin}/quotanest --help")
    assert_equal version.to_s, shell_output("#{bin}/quotanest --version").strip
  end
end
