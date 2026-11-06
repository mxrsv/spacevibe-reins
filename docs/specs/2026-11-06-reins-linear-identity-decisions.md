# Reins: Linear-referenced identity and polish, decision ledger

Source: grilling session 2026-11-06. Owner's words are quoted (Vietnamese originals translated; the original is kept where the wording matters).
Every later artifact (spec, plan, build prompt, subagent brief) cites these IDs (W20). Status: all rounds settled 2026-11-06; owner confirmed shared understanding.

## Problem

Owner: "UI trong app chưa rõ ràng, chưa có nhận diện riêng, chưa có gì đặc biệt, UI trông khá đơn giản, các UI chưa được trau chuốt, polish nhiều."

## Decisions

| ID | Decision | Owner's words |
| --- | --- | --- |
| D1 | Scope is every screen except Settings; Loadout, Rules, Activity, Limits and the shell are all unfinished. | "chỉ có setting là được polish rồi, còn lại tất cả đều chưa ổn" |
| D2 | Settings is not a reference or a bar; it is only a screen already polished. | "setting không phải mốc hay tham chiếu gì cả, nó chỉ một cái tôi đã polish rồi" |
| D3 | The single reference is the Linear desktop app. | "linear app desktop làm app tham khảo" |
| D4 | Take almost everything from Linear, colour included. | "có lấy màu, lấy gần như toàn diện" |
| D5 | Icons are recolourable like Linear's, as the main carrier of identity. | "tôi muốn dùng icon có thể đổi màu được như linear để nhận diện tốt" |
| D6 | Surfaces stay neutral; colour lives in the accent and in icons, as in Linear. | "q3 trung tính" |
| D7 | Earlier rules are relaxed wherever Linear differs (no-border cards, one vertical line, 12/14/16 only). Inter stays. | "q4 theo linear hoàn toàn đi" |
| D8 | Icon colour follows data state (verdict icons) and entity kind (skill, agent, hook, rule, CLI); user-chosen colours are not needed now. | "aprove" (recommendation of round 3, Q1) |
| D9 | One thin-stroke set replaces both Solar (sidebar) and the unbuilt Tabler page set; a second, custom state-icon set is drawn for verdicts. | "aprove" (round 3, Q2, option B) |
| D10 | Accent stays in the blue family, cleaner and deeper; 2-3 shades are shown in the mock for an eye pick. | "aprove" (round 3, Q3, option a) |
| D11 | Scope covers Linear's visual language plus its interaction primitives (`j/k` navigation, multi-select, peek panel, filter chips, visible shortcuts). The Matrix two-CLI columns and the per-CLI Rules pages stay; no change of overall layout. | "aprove" (round 3, Q4, option b) |
| D12 | The `PRODUCT.md` ban on gradients stays; depth comes from tonal layers, 1 px translucent hairlines and a top-edge highlight. | "aprove" (round 3, Q5, option a) |
| D13 | Dark is the primary appearance (as in Linear) with light kept at equal quality and verified every build. | "ok" (round 4, recommendation accepted) |
| D14 | App icon and the landing page (`site/`) follow later, not in this track, after the app is approved; the landing waits for the app's language already (see `2026-11-05-reins-landing.md`). | "ok" (round 4, recommendation accepted) |
| D15 | Plan v4 is replaced by a new Linear-based spec; only parts still right are kept (contrast test, sunken segmented track). | "aprove" (round 3, Q6, option B) |
| D16 | Process: at least 3 mock directions in a browser on the same sample screen (Loadout), light and dark; owner picks by eye; only then tokens and components in Swift. | "aprove" (round 3, Q7) |
| D17 | Layout of mock direction C (compact list left, permanent detail pane right) is the chosen layout. | "option C layout khá tốt" |
| D18 | The list's progress cell (Claude/Codex counts and bars at the right of each row) is redesigned; the current stacked count-over-bar cell is rejected. | "phần progress đang có vấn đề UI được tốt, cần có hướng tốt hơn cho phần UI vùng tôi khoanh đỏ" |
| D19 | Icons must not be taken straight from Linear; Reins uses its own verdict icon set and a different icon family. This refines D5 and D9 (recolourable and thin-stroke stay; Linear's own status glyphs go). | "icon không được lấy y nguyên của linear, nên đổi icon loại khác" |

## Facts found (not decisions)

- v4 plan: only V1 (spec, `2b2615f`) is done; V2-V8 not built.
- Current accent `#476EAE` light, `#A4BFEB` dark; no gradients, no illustrations, minimal motion (fades, toast, 0.15 s switch).
- Baseline screenshots (synthetic fixture home): `~/scratch/spacevibe-reins/identity-audit/`. The Limits run produced no PNG; cause not yet checked.

## Traceability still owed (W20)

Spec must map D1-D16 to a requirement ID and an acceptance check. The acceptance for "like Linear" compares the built app with the chosen mock side by side per surface (structure, content, look, theme), not tokens or test counts.
