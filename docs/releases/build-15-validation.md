# Build 15: source filtering, deliberate reading, and rounded resize controls

## Scope and baseline

The owner authorized a normal commit/push and replacement of the existing beta.5
DMG. Main history is preserved. The starting remote main commit was `5b2aea6`;
the old annotated beta.5 tag object was `04c6e6f81fdd6f9a758d65eab634cc433d7105e4`.
Build 12 was published; builds 13/14 were local previews. Build 15 retains
`dev.local.lens`, the existing Developer ID team, preferences, and beta.5 channel.

## Application verification

- Local full suite: 122 Swift Testing tests reported, three opt-in skips, and
  three XCTest checks passed. Coverage includes language filtering, reader
  snapshots/selection/scroll retention, late results, overflow lifecycle,
  resize geometry/security hiding, PNG composition, and silent MP4 encoding.
- Rounded-corner native drawing is continuous across four actual handle views
  at 1x/2x scale; light/dark synthetic renders were inspected.
- Actual preview execution confirmed source filtering on a multilingual fixture,
  reader text remaining fixed during a numeric/negation source change, explicit
  application replacing the affected row, and toolbar click-through unlocking.
  Minimize/restore left translation paused. Original Korean/Japanese selections
  and completed onboarding were restored and rechecked.
- These are bounded checks, not complete acceptance. See the detailed
  [interaction evidence and unresolved observations](../interaction-reading-validation.md).

## Distribution gates

At the original publication preflight, `release-signing` lacked the two Apple authentication inputs. Existing local Keychain authentication was successfully checked, and that authorized local fallback was used. This is a historical preflight result, not the current environment configuration; see the dated CI follow-up below. Ordinary development CI was not CI notarization.

- Application source: `1f5df5e44bb33a2aa438b52d3dbdd03762aedfc4`.
- [GitHub CI](https://github.com/kuil09/lens/actions/runs/35042310848) passed
  checks, unit tests, Release build, development DMG generation, and artifact upload.
- Local secure-timestamp Developer ID build 15 passed strict signature verification;
  the unchanged team is `GS344U4ZSG` and hardened runtime remains enabled.
- App submission `acaa14fb-638e-49d6-9261-c04bc7c9827b`: Accepted, stapled and validated.
- DMG submission `b60908b1-c925-407b-adb5-18d8f60f3332`: Accepted, stapled and validated.
- DMG and contained app both pass Gatekeeper as Notarized Developer ID.
  Read-only mounted app files match the signed build; build number, icon,
  license, Applications link, and compressed-image integrity were checked.
- The uploaded build-15 DMG and sidecar were downloaded again with GitHub CLI.
  SHA-256 and byte comparison matched; the downloaded image's internal app was
  separately mounted and passed the same signing/ticket/Gatekeeper checks.
- Final SHA-256: `4eb609fa06a03220d31a6e7f463f040a3fbe58af7d866196448ad8f6b9f0e8ac`.
- Publication replaces the build-12 asset pair only after validating the new
  download. Main history remains intact; release-tag changes use the recorded
  old object as a force-with-lease precondition. No installed app is replaced.

## Remaining limits

Actual physical body-input forwarding and corner dragging remain inconclusive
because automation did not establish the correct overlapping window target.
Live popover interaction, this candidate's real PNG/video saving, full VoiceOver,
administrator authentication, multiple displays, sustained use, and controlled
translation-quality evaluation are not established by automated tests. No
permission reset, quarantine removal, or security bypass is permitted. A beta
publication does not imply that these gaps are closed.

## CI follow-up — 2026-09-16

This section records CI verification after the local build-15 publication. It does not change that public artifact's provenance or claim a replacement was published.

- The owner registered the Apple authentication Secrets. The existing four required environment Secret names and team variable were verified without revealing their values. Reviewer protection and the main-only deployment restriction were preserved.
- [Run 35045717231](https://github.com/kuil09/lens/actions/runs/35045717231), source `9a8a5caed05bbaa1f817ced3ec572c225b1790e5`, was approved and passed preflight, checks/tests, certificate/private-key import, Developer ID signing, real Apple authentication and app upload.
- App submission `41a36ff7-547d-4df6-80e8-e52da07a4450` was **Invalid**. Apple's existing-submission log identified `com.apple.security.get-task-allow` on the arm64 executable. No DMG was submitted and no CI deliverable was uploaded; cleanup ran. Authentication success did not establish notarization success.
- CI had omitted the base-entitlement injection override used by local signing. Commit `17d4ec7150210766cc718182c90939331766eae7` adds `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` plus signed-binary entitlement validation before submission. Local checks passed: 49 index assertions, 49 shell assertions, 4 installer tests and 13 notarization/preflight tests. These tests are not another Apple acceptance.
- [Corrected run 35046508807](https://github.com/kuil09/lens/actions/runs/35046508807) was **waiting for release-signing review** at the September 16 documentation check. Check that run for later changes; this snapshot is not a live status feed. This documentation pass did not dispatch, approve or retry it.
- The existing public build-15 DMG/sidecar names and digest still matched the local-notarization record above. No release, tag, DMG, installed app, user setting or Secret was changed by the documentation pass.
