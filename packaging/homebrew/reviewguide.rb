class Reviewguide < Formula
  desc "Review guides: the story of a code change, told next to every changed line"
  homepage "https://github.com/nevyn/ReviewGuide"
  url "https://github.com/nevyn/ReviewGuide/releases/download/v0.0.0/reviewguide-0.0.0-macos-universal.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  depends_on macos: :sonoma

  def install
    # The resource bundles must sit beside the real executable; bin gets a symlink.
    libexec.install "reviewguide", Dir["*.bundle"]
    bin.install_symlink libexec/"reviewguide"
    doc.install "licenses"
  end

  test do
    assert_match "# Story format", shell_output("#{bin}/reviewguide format")
  end
end
