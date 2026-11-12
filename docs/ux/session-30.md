# Session 30 — refinements (the user's list of 2026-11-12)

The user's twelve points, with screenshots, after #55. Backlog: B118, I493–I505. This brief covers what session 30
builds in tranches 1 and 2; the web dock (I495–I499) extends `docs/ux/webdock.md`, groups and "any module anywhere"
(I500 c, I501, I502) get `docs/ux/groups.md` before they are built.

The user's answers (2026-11-12): named groups after Noctalia v5's capsule groups; the bar's automatic grouping stays as
it is today by default; a card is at most ½ its screen's height and ⅓ its width; Settings in a sidebar is the full
app, docked into the sidebar's frame.

## 1. Cards kept ready, opened at their size (I493, B114)
**Others.** macOS keeps a menu-bar extra's window alive and re-shows it; GNOME Shell keeps its quick settings actor
built (it is always in the stage); KDE Plasma keeps plasmoid popups loaded once opened; Quickshell shells
(Caelestia, end-4) keep their popouts' items and only hide them. All open at their final size: the window is never
grown from nothing.
**Here.** `bar.card_keep_loaded` (on): a closed card keeps its view a minute (as `sidebar.keep_loaded`, K139), so a
second opening needs no making. The opening's spawn animation starts from the card's measured size (the view is
made, laid out, then the form runs), as the sidebar and launcher do since K135.
**States.** First opening (made, then shown); kept (shown at once); setting off (made each time); a card whose content
changes size while kept (its size follows before it is shown again).
**Budget.** A kept card is unmapped: 0 frames; PSS during the minute measured against BENCH.

## 2. Scroll edges (I494)
**Others.** iOS 26 sheets and toolbars: a progressive blur ("scroll edge effect") under bars where content scrolls
beneath; macOS Tahoe the same for toolbars; Android 16 fades list ends; GNOME's `GtkScrolledWindow` draws an
undershoot shade at a cut edge; KDE shows a hairline. Caelestia fades its launcher list's ends with an opacity mask.
**Here.** `theme.material.scroll_edges` = Blur (default), Fade, Cut. Where content is cut by a view's edge, a short
zone (at most 28 px, 14 % of the view) blurs it more and fades it more toward the edge; an edge with nothing beyond it
is drawn plain, the effect easing in over the zone's length as content goes under it (no step at the ends). One
component (`components/ScrollEdge.qml`, `shaders/scroll_edge.frag`): sidebars (column, page, tabs), the notification
centre, the launcher's list and emoji grid, cards that scroll (§7).
**a11y.** Nothing is hidden from the accessibility tree; the scroll bar stays above the effect.
**Ma.** Drawn through the view's layer only while the view can scroll; nothing redraws while nothing scrolls.

## 4a/4b. Sidebars: width per monitor, tabs in one row (I500)
`sidebar.<side>.width` is per output: a drag on one monitor writes that monitor's width. Tabs: one row, never wrapped;
when they do not fit they scroll sideways (wheel, touchpad, drag) with the row's cut ends blending out (§2), and the
current tab is always scrolled into view (Ctrl+PageUp/Down too). The pin moves into the tab row's outer end.

## 5. Text spawn on all text (I503)
`theme.typography.fx.scope = all` now means all text a surface shows as it opens: a surface that opens walks its text
once and gives each plain label a spawn (made once per label, kept); headings keep their own. Off by default (scope =
titles). Ma: nothing is made unless spawn is on and the scope is all.

## 6. The opening's face blends into the final one (I503, B112)
The form's picture and the card at rest are one face: where a form ends on a surface whose wash, material or pattern
is drawn differently at rest, the two cross-fade over a short time (`motion.std`) instead of switching in one frame.
Fix at the root first (B111's window-aligned SheetRest for Stage cards, polkit, the notification centre, toasts).

## 7. Cards have a maximum size and scroll (I504)
`bar.card_max_height` (50 % of the screen's height), `bar.card_max_width` (33 % of its width, never below what the
card needs to stay usable). A card taller than its limit stands at the limit and its body scrolls, with scroll
edges (§2) and the look's scroll bar; keyboard focus moving into a row below the fold scrolls it into view.

## 8. Notification cards and OSD follow the style system (I505)
Corner shape, outline colour (`Theme.surfaceLineColor`), material, elevation, text effects and fonts as any card.

## 9. The launcher at the edge follows the theme (I505)
Opened from a bar button and standing on that bar (I428), it is one sheet with the bar — with the frame's outline,
its corner shape and the fillets the Stage's cards have.

## 10. Even margins for floating cards (I504)
A floating card keeps one gap (the gap between the card and the screen's edge, the user's reference) to every
surface or edge it stands near: the bar, the frame's inner edge, the screen's edge, a pinned sidebar.

## 11. Settings: no Reset that changes nothing (I505)
Reset shows only where a reset changes the value: the layer under the user's (profile, style, default — `cfg.why`)
holds another value. A user value equal to the layer below keeps its provenance chip (it is still the user's).

## Definition of done (tranches 1–2)
Each item seen on nested niri with the user's profile (`red-wood-splatting`) in dark and light, at rest and in motion
where it moves; the merge set and `just check` green; PROGRESS tracks functional and UX apart; the user judges in
motion on two monitors (B96 stands until they do).
