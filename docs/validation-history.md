# Historical verification boundaries

This summary preserves useful evidence and limitations from the pre-consolidation repository. It is not acceptance of the current source or a download index. Superseded release notes, diagnostic transcripts, and source history were backed up before cleanup. Current artifact provenance belongs to the public release notes.

## Automated and native observations

- Early synthetic Vision/backoff tests checked exact numeric/negation changes, stale replies, paragraph grouping, local masking, bounded work, and fairness. Fake translation engines and injected clocks establish algorithm behavior, not Apple translation quality or desktop latency.
- Earlier native checks observed source-language filtering, stable manual reader updates, toolbar interaction while body click-through was enabled, successful PNG capture, and silent MP4 finalization. A physical-input counter experiment had an invalid negative control; it did **not** establish cross-app click/drag/scroll routing. Detached light/dark renders likewise did not establish full VoiceOver or live contrast acceptance.
- English, Korean, and Japanese launches were observed during early localization work. Full linguistic review and end-to-end accessibility were not performed.
- Before consolidation, source `dbf3a0d` passed 175 local regression tests and general CI. Synthetic-document recordings of about 101 and 104 seconds decoded completely, with zero reported encoder drops. Inspected moving frames included both maintained translations and original-text fallback. QuickTime playback was observed, but not continuously frame by frame. These observations are neither a controlled performance gain nor complete translation coverage.
- Source `0e3a765` passed focused return/handoff tests and general CI. A 58.465-second recording decoded all 876 frames, and the user reported ordinary System Settings visits working. Some automated foreground observations were inconclusive; the human confirmation is distinct from an instrumented input test. Existing grants were not revoked to exercise the explicit permission button.

## Serial test mitigation

Hosted-runner parallel tests stalled while local execution did not reproduce the same outcome. A controlled hosted serial run passed; local and CI now use `swift test --no-parallel`, with assertions intact. This mitigates the observed stall but does not prove its root cause or resolve every concurrency risk. General CI has bounded diagnostics and an 8-minute test watchdog. Signing requires successful main-push CI for exactly the dispatched SHA.

## Retired artifact provenance

| Artifact | Source | SHA-256 | Verification at the time |
| --- | --- | --- | --- |
| beta.4 / build 10 | `6cce73a` tag target | `d035494a6162e1de3251d6ce797a8376fcfc13bbf22133de94dcac60991092f9` | Developer ID signed; **not notarized** |
| beta.5 / build 15, CI package | `277506f` | `2ba8739570853d700921bcdbc9ef0509d4709b6ec89d28aaacb7488563f682ed` | App/DMG Accepted, stapled, strict signatures and Gatekeeper passed; public bytes verified |
| beta.6 / build 16 | `dbf3a0d` | `7af0ef4ab2c22b9fee9525705928a24fc8b6ee10d5ff64721016c55c452265cb` | App/DMG Accepted, stapled, strict signatures and Gatekeeper passed; public bytes verified |

Beta.5 used [protected CI](https://github.com/kuil09/lens/actions/runs/35052988016), app submission `ca1e4bc5-39c7-499a-83f1-4499c5a304bc` and DMG submission `197220a9-690e-4ed5-b5d3-efdb52e00b62`. Its downloaded app was copied into Applications and smoke-tested; a browser-quarantined clean-machine drag-install was not established.

Beta.6 used [protected CI](https://github.com/kuil09/lens/actions/runs/35092717950), app submission `77f829d9-9d8e-4536-ad0e-19033dcac306` and DMG submission `c8a0745f-b069-4f93-86b5-d96f7caa56b2`. Public-download verification was completed; a fresh install/runtime test of that public CI binary was not.

Beta.7 / build 17 passed [general CI](https://github.com/kuil09/lens/actions/runs/35153810994) and [the notarization workflow](https://github.com/kuil09/lens/actions/runs/35154368113), but was not publicly released before consolidation. Workflow success alone was not reported as independent public-file validation.

## Limits retained for future checks

External displays, actual administrator-authentication input, clean-machine permission recovery, long-duration thermal/memory behavior, full keyboard/VoiceOver flows, six-direction linguistic quality, and complete physical body-input routing are not certified by these records. Security acceptance, automatic tests, native observations, and user acceptance remain separate evidence. Do not reset permissions, delete language packs, disable Gatekeeper, or remove quarantine merely to make a test pass.
