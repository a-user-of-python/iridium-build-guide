# Iridium build guide

Builds the [Iridium](https://github.com/a-user-of-python/iridium) iOS app
(with the DX10 compatibility shims) to an unsigned `.ipa` from your Mac.

## Download and run

On your Mac, open Terminal and run:

```sh
curl -L -o iridium-ipa-build.sh \
  https://raw.githubusercontent.com/a-user-of-python/iridium-build-guide/main/iridium-ipa-build.sh
bash iridium-ipa-build.sh
```

The script:

1. Clones (or updates) `a-user-of-python/iridium` into `~/Desktop/iridium`
   and checks out the `dx10-shim-frontends` branch.
2. **Apple Silicon Mac:** runs the repo's own local IPA build
   (`ci/build-local-ipa.sh`). First run takes several hours; later runs
   reuse everything that did not change.
3. **Intel Mac:** Iridium's build scripts require Apple Silicon for local
   compilation, so the script instead dispatches the repo's official
   "Build unsigned IPA" workflow on GitHub's Apple Silicon runners, waits
   for it, and downloads the finished `Iridium-unsigned.ipa`.

## One-time setup

- Install Xcode (free, Mac App Store).
- Intel Macs also need the GitHub CLI, logged in:
  `brew install gh` then `gh auth login`.
- Enable Actions on the Iridium fork once (GitHub disables Actions on
  forks by default):
  https://github.com/a-user-of-python/iridium/settings/actions

## After the build

The IPA is **unsigned**. Sign it with Sideloadly, AltStore, or your
preferred sideloading tool before installing on a device. JIT, game
playback, audio, and input need separate device tests.
