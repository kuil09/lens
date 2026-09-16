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

At preflight, `release-signing` still lacks `LENS_APPLE_ID` and
`LENS_APPLE_APP_PASSWORD`. Existing local `Lens-notary` authentication was
successfully checked. The authorized local fallback will be used; ordinary
GitHub development CI is not CI notarization.

Source commit, CI outcome, app/DMG submission IDs, mounted-content checks, and
public download checksum will be recorded only after those operations succeed.
Until then build 15 is a candidate, not a verified replacement.

## Remaining limits

Actual physical body-input forwarding and corner dragging remain inconclusive
because automation did not establish the correct overlapping window target.
Live popover interaction, this candidate's real PNG/video saving, full VoiceOver,
administrator authentication, multiple displays, sustained use, and controlled
translation-quality evaluation are not established by automated tests. No
permission reset, quarantine removal, or security bypass is permitted. A beta
publication does not imply that these gaps are closed.
