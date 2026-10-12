# Homebrew formula

`storygrafter.rb` is the source of the formula that `brew install nevyn/tap/storygrafter` installs. The tap, [nevyn/homebrew-tap](https://github.com/nevyn/homebrew-tap), holds a generated copy at `Formula/storygrafter.rb`; edit this file, never the tap's copy, because every release overwrites it. Its `url` and `sha256` are placeholders that the release workflow rewrites.

The formula installs the universal `storygrafter` binary and its resource bundles into `libexec` and links the binary into `bin`.

## Releasing

```
scripts/release.sh 0.2.0   # tags v0.2.0 on origin/main and pushes the tag
scripts/release.sh redo    # deletes the latest release and its tag, then tags the same version on origin/main again
```

The tag starts `.github/workflows/release.yml`, which stamps the version into the binary, tests, builds for arm64 and x86_64, publishes the GitHub release with notes from the commits since the previous tag, and points the tap's formula at the new tarball.

## `TAP_TOKEN`

The tap job pushes to another repository, which the workflow's own `GITHUB_TOKEN` cannot. It uses the repository secret `TAP_TOKEN`: a fine-grained personal access token with access to `nevyn/homebrew-tap` only and the repository permission **Contents: Read and write**. When it expires, the tap job fails while the release itself stays published; renew the token and re-run the tap job.
