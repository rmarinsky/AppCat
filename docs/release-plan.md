# AppCat Release Plan

## Current AppCat Release

PR #12 is the clean-break AppCat release.

- Label: `release:major`
- Latest tag before this work: `v1.7.3`
- Expected AppCat tag on merge: `v2.0.0`
- Product identity: `AppCat`
- Bundle IDs:
  - Release: `ua.com.rmarinsky.appcat`
  - DEV: `ua.com.rmarinsky.appcat.dev`
- App support path: `~/Library/Application Support/AppCat`
- App icon: orange macOS icon with white cat symbol

This is intentionally not a seamless BrowserCat update. It is a new app identity.

## Release Automation

The release flow is label-driven:

1. PR into `main` must have exactly one release label:
   `release:major`, `release:minor`, `release:patch`, or `release:skip`.
2. When the PR is merged, `.github/workflows/prepare-release.yml` computes the next tag from existing `v*` tags.
3. `prepare-release.yml` pushes the tag and dispatches `.github/workflows/release.yml`.
4. `release.yml` builds `AppCat.app`, exports a Developer ID build, notarizes it, creates `AppCat-<version>.dmg`, signs the DMG for Sparkle, creates the GitHub release, and publishes the appcast on `gh-pages`.

`project.yml` version values are placeholders. The git tag is the source of truth for `MARKETING_VERSION`; `git rev-list --count HEAD` is used as the build number.

## Sparkle For AppCat

AppCat uses:

```xml
<key>SUFeedURL</key>
<string>https://rmarinsky.github.io/AppCat/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>E+U25RLLvknFBaJXFMZ5YnpN4gRJLsavDNEGc+M2xk0=</string>
```

The live Sparkle feed is the `appcast.xml` file on the `gh-pages` branch. `docs/appcast.xml` in `main` is only a clean template/reference.

Do not manually edit the live appcast for normal releases. The release workflow does this:

- generates `AppCat-<version>.dmg`
- signs it with `SPARKLE_EDDSA_PRIVATE_KEY`
- writes `sparkle:edSignature` and `length` into the appcast
- appends one item per release

Sparkle keys do not need to change for AppCat as long as:

- `SUPublicEDKey` in `Info.plist` still matches the private key in the GitHub secret `SPARKLE_EDDSA_PRIVATE_KEY`
- every update DMG is signed with that private key
- appcast entries are generated from actual AppCat DMGs, not renamed BrowserCat artifacts

Reference: Sparkle uses appcasts from `SUFeedURL` and requires signed update enclosures for EdDSA-secured updates: <https://sparkle-project.org/documentation/>

## GitHub Pages Constraint

`SUFeedURL` currently points to:

```text
https://rmarinsky.github.io/AppCat/appcast.xml
```

That URL only matches the normal GitHub Pages project path if the repository is named `AppCat` or a custom Pages setup serves that path.

The current remote is still:

```text
git@github.com:rmarinsky/BrowserCat.git
```

If the repo stays named `BrowserCat`, the normal project Pages URL is:

```text
https://rmarinsky.github.io/BrowserCat/appcast.xml
```

GitHub repository redirects do not solve this for Sparkle. GitHub documents that repository rename redirects do not apply to project site URLs. Reference: <https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository>

So before merging/releasing AppCat, choose one:

- Rename the GitHub repository to `AppCat`, then keep the current `SUFeedURL`.
- Keep the repo as `BrowserCat`, then change AppCat `SUFeedURL` back to `/BrowserCat/appcast.xml` and accept the technical URL mismatch.
- Use a custom domain/user Pages setup that can serve stable `/AppCat/appcast.xml` and `/BrowserCat/appcast.xml` paths.

Given the product direction is "fully AppCat", the cleaner choice is to rename the repo to `AppCat`.

After renaming the repo, update local remotes:

```bash
git remote set-url origin git@github.com:rmarinsky/AppCat.git
```

## BrowserCat Bridge Release

Old BrowserCat users still look at the old BrowserCat feed and have the old bundle ID. They will not automatically become AppCat through this clean-break release.

A safe bridge base branch has been created:

```text
browsercat-bridge-base
```

It points to current `origin/main` before the AppCat merge.

Bridge release scope:

- Keep old product identity: `BrowserCat`
- Keep old bundle ID: `ua.com.rmarinsky.browsercat`
- Keep old app support path: `~/Library/Application Support/BrowserCat`
- Keep old Sparkle feed URL: `https://rmarinsky.github.io/BrowserCat/appcast.xml`
- Ship a final BrowserCat patch release, likely `v1.7.4`
- Show a migration/download prompt that opens the AppCat release page
- Do not try to silently replace BrowserCat with AppCat through Sparkle

If we rename the repository before shipping/preserving the old BrowserCat Pages feed, old BrowserCat Sparkle checks can break. Either ship the bridge first while the old project Pages URL exists, or host the old BrowserCat appcast from a stable custom/user Pages path.

## Recommended Order

Best reliability:

1. Build the BrowserCat bridge from `browsercat-bridge-base` and publish it as the final BrowserCat update.
2. Confirm `https://rmarinsky.github.io/BrowserCat/appcast.xml` still serves that bridge release.
3. Rename the repository to `AppCat`.
4. Merge PR #12.
5. Let `release:major` publish AppCat `v2.0.0`.
6. Confirm `https://rmarinsky.github.io/AppCat/appcast.xml` serves the AppCat feed.

Fast clean-break path:

1. Rename the repository to `AppCat`.
2. Merge PR #12.
3. Let `release:major` publish AppCat `v2.0.0`.
4. Accept that old BrowserCat users need a manual download path unless the old feed is separately preserved.
