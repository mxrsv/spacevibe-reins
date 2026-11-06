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
| D18 | SUPERSEDED by D23 (the list has no counts). The list's progress cell (Claude/Codex counts and bars at the right of each row) is redesigned; the current stacked count-over-bar cell is rejected. | "phần progress đang có vấn đề UI được tốt, cần có hướng tốt hơn cho phần UI vùng tôi khoanh đỏ" |
| D19 | Icons must not be taken straight from Linear; Reins uses its own verdict icon set and a different icon family. This refines D5 and D9 (recolourable and thin-stroke stay; Linear's own status glyphs go). | "icon không được lấy y nguyên của linear, nên đổi icon loại khác" |
| D20 | Icon colour is used only to tell categories apart (Skills, Agents, Hooks); sidebar icons are white (the foreground colour; ink in light mode); list items use one identical grey icon each. This narrows D5 and D8: the per-item verdict icon leaves the list and the verdict shows in the detail pane. | "chỉ dùng màu icon khác nhau cho các danh mục như agent, skill thôi, còn sidebar icon dùng màu white đi, còn các item thì dùng màu hơi xám và icon giống nhau đi" |
| D21 | Each row ends with a strip of CLI logos (only CLIs detected on the machine). A logo is lit with a success badge at its corner when the item exists in that CLI, dim when it does not. Clicking a dim logo adds the item to that CLI (toast with Undo); clicking a lit logo does nothing. Replaces the "Add to Codex" button and the empty Codex column. | "thêm skill cho các agent cli kia bằng cách hiển thị một list logo agent ở đó, agent nào thêm thì có thể click vào logo đó và hiển thị một icon success ở góc logo" |
| D22 | Hovering a logo opens a popover: CLI name and status, the action (`Add to <CLI>` or `Open file`), and the reason when it cannot be added (plugin-owned, read-only). No run counts in it. | "thêm một popover khi hover vào mỗi logo agent" + "ok hết" (options a, c, d) |
| D23 | Run counts appear only in the detail pane. The list has no count or bar column; each row is grey icon, name, logo strip, warning icon when abnormal. Supersedes D18; narrows D11 (the Matrix lives in the strip and the pane, not in list columns). | "số lần chạy skill thì hiển thị trong trang detail" |
| D24 | Abnormal rows carry a warning icon at the row end; hover or keyboard focus opens a tooltip or popover. Normal rows stay empty there. States: Never ran (warn tone), Dead (danger tone), Not measured yet (neutral icon, not a warning). The popover gives a plain sentence and `Remove` / `Open file`; Remove has Undo. | "cần một icon warning để khi hover vào sẽ có tooltip hiển thị hoặc popover hiển thị ra" + "ok hết" |
| D25 | The logo strip shows only CLIs detected on the machine; Reins writes only to Claude Code and Codex. | "ok hết" (recommendation accepted) |
| D26 | Categories are separated by tabs above the list (`Skills · Agents · Hooks · All`) plus thicker group headers (40 px, own fill, sticky, collapsible, with a composition strip). Inside a category tab, groups are by verdict (heavily used, used, never ran, dead). The `All` tab groups by kind. | "ok hết" (recommendation accepted; trigger: "phần danh mục này chưa phân biệt được rõ và nhìn chưa tách biệt với các item") |
| D27 | `Group by` (kind, verdict, CLI presence) and `Order by` (name, run count, last run) as in Linear; default order is run count, descending. | "ok hết" (recommendation accepted) |
| D28 | Multi-select with `x` shows the same logo strip in the bottom bar, to add all selected items to one CLI in one click. | "ok hết" (recommendation accepted) |
| D29 | The top of the list is simplified and no longer mirrors Linear: no title bar (the sidebar already names the screen); a single row holds the category tabs on the left and scope, Filter and View on the right. Each tab carries an icon beside its text and its own colour (Skills violet, Agents teal, Hooks amber, All neutral); each tab sits on its own tinted chip (the tab colour at about 12%), stronger when hovered and strongest with a 1 px ring when selected; no underline. Mock-only controls (header treatment, accent, theme) move to a floating panel outside the app frame. | "phần trên này đang quá giống Linear, cần tối giản đi, ví dụ Head đầu tiên không cần, nó chỉ là title, còn tab Skill, Agents, Hooks, All cần cho chúng icon nằm cạnh text, mỗi tab item sẽ dùng 1 màu khác nhau" + "mỗi tab item phải có background chip ấy" |

## Facts found (not decisions)

- v4 plan: only V1 (spec, `2b2615f`) is done; V2-V8 not built.
- Current accent `#476EAE` light, `#A4BFEB` dark; no gradients, no illustrations, minimal motion (fades, toast, 0.15 s switch).
- Baseline screenshots (synthetic fixture home): `~/scratch/spacevibe-reins/identity-audit/`. The Limits run produced no PNG; cause not yet checked.

## Traceability still owed (W20)

Spec must map D1-D16 to a requirement ID and an acceptance check. The acceptance for "like Linear" compares the built app with the chosen mock side by side per surface (structure, content, look, theme), not tokens or test counts.
