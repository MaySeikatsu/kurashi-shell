#!/usr/bin/env python3
"""Sorts docs/BACKLOG.md's open rows into batches and writes docs/BACKLOG-BATCHES.md. Fails if a row is in no batch
or in two."""
import re
import sys

ROOT = sys.argv[1]
CLOSED = ("done", "fixed", "rejected", "obsolete", "withdrawn", "dropped")

# (section, batch title, what the rows share, size, what it needs from the user, ids)
B = [
 ("1. Quick polish (hours to a day each, user-facing)", [
  ("Launcher, small", "the launcher's prefix handling and its rows; one suite, one niri look. Also the inbox line `> note <text>` (tasks; no row)", "S", "—",
   "I539 I572 I138"),
  ("Web dock in the bar", "the dock's bar widget and the mod's `[[menu]]` rows; the five suite rows are one failure (a click on the widget does not ask for the card)", "S–M", "I600: one module per pinned site, or one module listing them",
   "I599 I600 I69 I73 B131 B123 B69 I403 I434"),
  ("Settings, fixes", "the Settings app's own code (search, reconnect, the sheet host, `Label`); one screenshot round", "S–M", "—",
   "I597 I334 I361 I352 I351 I601 I589 I81 B59"),
  ("Mods page and Mod Editor", "the Mods page and the `mods` document (one contract change for I605 and I593)", "S–M", "—",
   "I604 I605 I593 I592 I575 I215 I195"),
  ("Quick settings, small", "the quick card and the control modules", "S–M", "—",
   "I586 I204 I108 B71 B72 B73 B75 I484 I326"),
  ("Wallpaper picker", "the picker's card (I538 and I83 are the same wish: more room for the pictures)", "S–M", "—",
   "I538 I83 I32 I135 B88"),
  ("Icons and glyph sizes", "`Icon.qml` and the bar's glyph metrics", "M", "—",
   "B61 B52 B62 B70 I214"),
  ("Media, small", "the media face and Dynamic Media Color", "S–M", "I398: which option",
   "I133 I398 B89"),
 ]),
 ("2. Passes over one area (one to a few days each)", [
  ("Settings, structure", "the pages' order and sections; I474 and I151 belong here because the Sidebar page and the sidebar's toggles change together", "M–L", "design questions up front (I595, I596, I598 are your reports)",
   "I595 I596 I598 I464 I479 I104 I573 I251 I474 I151"),
  ("Settings, theming pages", "the palette, profile and recipe lists in Settings", "M", "—",
   "I147 I153 I335 I359 I360 I343 I369"),
  ("Settings docked in a sidebar", "the dock's focus and watching of the Settings process", "M", "—",
   "B127 B129 B130"),
  ("Applying a style", "how a style, a profile's own theme entries and run-time packs layer (I280 is your report: \"picking a style does nothing\")", "M", "—",
   "I280 I146 I294"),
  ("Bars and layout", "the layout document, zones and holders, side bars", "M–L", "—",
   "I85 I221 I250 I266 B51 B97 B121 B139 I237 I240 I264 I265 I271"),
  ("Sidebars", "the sidebar's window and sections", "M", "I465: how a hover-opened sidebar closes",
   "I500 I152 I465 I150 I149 I255"),
  ("Edit mode and groups", "dragging things into place on the screen: modules, desk cards, groups", "L", "a UX brief first (I220)",
   "I220 I222 I101 I502 I508 B74"),
  ("Peeks", "the Stage's peek sources (`ui.peek`); I257 and I602 are the same clock peek", "M", "—",
   "I67 I602 I257 I258 I466 I47"),
  ("Island", "the island's surface, faces and card", "M–L", "I1: the model",
   "I1 I112 I113 I212 I256 I260"),
  ("Cards and scrolling", "the Stage's cards and the shared scroll host", "M", "—",
   "I494 I504 I505 I332 I324"),
  ("Notifications", "the notification service and centre", "M–L", "I529: which parts first",
   "I529 I205"),
  ("Desk", "the desk surface and its cards", "S–M", "—",
   "I196 I125"),
  ("Lock and greeter", "the lock, the greeter and its cache", "M", "—",
   "I142 I416 B67"),
  ("Web dock, card and host", "the dock's card, the host process and its settings", "M–L", "—",
   "I78 I79 I97 I106 I431 I207 I159 I74 I92 I94 I91 B122 B107 B117 B94 B95 I80"),
  ("Bundled mods, follow-ups", "one visit per mod: weather (I57 I82 I88 I66), calendar (I89 I203), sysmon (I84), tasks (I120 I121), timer (I229 I236), lyrics (I129), easter eggs (I286)", "M", "—",
   "I57 I82 I88 I66 I89 I203 I84 I120 I121 I229 I236 I129 I286"),
  ("Fonts and handwriting", "the font list, the mix and the handwriting mod", "M", "—",
   "I440 I444 I419 I446 I415"),
 ]),
 ("3. Larger features (several days each; a UX brief first)", [
  ("Audio control", "PipeWire devices and streams in the quick card, the sidebar and the island", "M–L", "—",
   "I524 I111 I20"),
  ("Quiet time", "one mechanism: hold notifications and summarise them after", "L", "the brief",
   "I520 I534 I530"),
  ("niri config from Settings", "one writer of niri config with a live preview and a revert countdown", "L", "the brief",
   "I528 I535 I533"),
  ("Windows and previews", "the window list, the previews and a switcher", "M–L", "I414: the default for previews",
   "I521 I197 I413 I414"),
  ("One search and quick capture", "the launcher's ranking over more sources; capture to the vault is one more sink", "L", "the brief",
   "I518 I532"),
  ("AI mod", "the AI mod and its launcher mode", "L", "—",
   "I525 I141"),
  ("Any module on any surface", "a module's forms for bar, sidebar, card, web dock; other windows hosted by the shell", "L", "the model (I501)",
   "I501 I490 I499 I509 I510 I513 I372 I385 I409 I468 I476 I144"),
  ("Module variants (K72)", "a glance, a peek, a tile and a desk card for the core modules; the control centre as modules", "L", "—",
   "I223 I224 I225 I226 I227 I228 I469"),
  ("Web dock, engine", "the web engine and what a page may do; I391 and I394 wait for the overhaul (I402)", "L", "I371: the engine",
   "I498 I371 I373 I377 I71 I70 I75 I402 I391 I394"),
  ("Mod catalogue", "the index and installing from it (W98 steps 2–7)", "L", "read the brief",
   "I526 I570 I564"),
  ("Gestures", "motion that follows the finger", "L", "—",
   "I531 I346"),
  ("Standalone features", "nothing shared: each is its own card (screen tools, phone link, config timeline, accessibility pack)", "L each", "which, if any",
   "I522 I523 I536 I537"),
 ]),
 ("4. The visual system (looks, motion, light)", [
  ("Looks and chrome, fixes", "the chromes, shadows and corner shapes", "M–L", "B79 (Glow) is your report",
   "B79 B81 B86 I122 I123 I160 I161 I188 I269 I288 I310 I471 I489 I492 I103 I470"),
  ("Style families", "one family at a time, with you (I336), each against its inspiration (I289)", "L", "a review session per family",
   "I336 I289 I325 I327 I328 I381 I117 B82"),
  ("Joins", "the two join builders (`ColumnShape`, `MorphShape`) become one, then the open join cases", "M–L", "—",
   "I588 I483 I491 I245"),
  ("Frame", "`Frame.qml` and its strips", "M", "—",
   "I132 I230 I239 I268 I304"),
  ("Motion, fixes", "the motion engine and the forms; B80 (paint forms) is your report", "M–L", "judge in motion (B96)",
   "B80 B90 B91 B98 B102 B104 B112 B115 B32 I180 I186 I199 I273 I315 I354 I363 I387 I388 I389 I472 I478 I486 I487"),
  ("Motion, new", "new forms and where motion can go next", "L", "—",
   "I348 I349 I350 I347 I448 I412 I368"),
  ("Text effects", "`TextFx` and text spawn", "L", "—",
   "I485 I473 I425 I503"),
  ("Light, texture and effects", "the texture's light, screen effects, the cursor", "L", "—",
   "I173 I313 I312 I317 I165 I384 I380 I182 I450 I461 I462"),
  ("Wallpaper, ideas", "the wallpaper as a live or derived picture", "L", "—",
   "I519 I401 I323"),
  ("Theme in other apps and compositors", "the theme export's targets", "M–L", "—",
   "I480 I454 I366 I367 I443 I442 I429 I202 I421 I370 I481 I164"),
 ]),
 ("5. Parked: the structure and performance session", [
  ("Memory and performance", "B156 first; one soak and one bench run serve most rows", "L", "—",
   "B156 B153 B149 B148 B35 B119 B120 B101 B114 I493 B100 B57 B58 B84 B56 I463 I417 I10 I11 I22 I238 I254 I272 I342 I261 I344 I587 I211 I216 I218 I158 I404 I178 I320"),
  ("Structure: the core and the mods", "W92 rows 4–6, W95, and what the code repeats", "L", "—",
   "I571 I574 I555 I556 I557 I560 I565 I566 I77 I590 B39 B40 I548 I558 I550"),
  ("Mod API additions", "`ModCtx` and the manifest (I231 and I591 are one: a mod posts a notification through the daemon)", "M", "—",
   "I231 I591 I233 I234 I235 I134 I118 I145 I24 I554"),
  ("Daemon, schema, adapters", "the daemon's own gaps", "M", "—",
   "B41 B66 I358 I139 I143 I208 I15 I42 I95 I177 I353"),
  ("Suites and test tools", "W96 and the suites' tooling; several rows are one failure seen twice (I87 = I580, B85 = I406, B68 = I318, I162 = I287)", "L", "—",
   "B145 I594 I603 I584 I585 B154 B155 B76 B87 B83 B92 I578 I580 I87 I582 I13 I107 B30 I179 I181 I213 I217 I241 I243 I246 I247 I248 I249 I252 I262 I263 I267 I274 I275 I287 I162 I308 I314 I318 B68 I321 I333 I355 I356 I357 I364 I365 I382 I383 I395 I405 I406 B85 I411 I432 I583 B77 B49 B50 B54 B55 B60 B63 B64 B43 I542 I544 I546 I549 I307 I362"),
  ("Mock parity", "`kurashi-mock`'s documents", "S", "—",
   "I157 I306 I581"),
  ("Nix", "the flake and the Home-Manager module", "S", "—",
   "I316 I378 B65"),
  ("Docs and process", "the docs themselves; I568 is the backlog triage with you", "S–M", "I568",
   "I449 I559 I568 I379 D1 D2"),
 ]),
 ("6. Check and close first (probably done, or decided)", [
  ("Rows whose status is behind", "each was built or decided, by its own text or by session 35: verify, then set the status", "S", "—",
   "I127 I232 I96 I569 I545 I551 B113 I547 I552 I563 I576 I577 I579 B147 I475 I477 I506"),
  ("Review with you", "only you can judge these, on your own session", "—", "a sitting",
   "B96 I219 I482"),
 ]),
]


def rows():
    out = {}
    for line in open(f"{ROOT}/docs/BACKLOG.md"):
        if not line.startswith("| "):
            continue
        c = [x.strip() for x in line.strip().strip("|").split(" | ")]
        if len(c) < 5 or set(c[0]) <= set("-: ") or c[0] in ("#", "ID"):
            continue
        if c[-1].lower().startswith(CLOSED):
            continue
        text = re.sub(r"\*\*", "", " | ".join(c[3:-1])).replace("|", "/")
        if len(text) > 120:
            text = text[:120].rsplit(" ", 1)[0] + " …"
        user = "user" in c[2].lower()
        out.setdefault(c[0], (text, user, c[-1]))
    return out


def main():
    open_rows = rows()
    seen = {}
    for _, batches in B:
        for title, _, _, _, ids in batches:
            for i in ids.split():
                if i in seen:
                    sys.exit(f"{i} is in two batches: {seen[i]} and {title}")
                seen[i] = title
    missing = [i for i in open_rows if i not in seen]
    unknown = [i for i in seen if i not in open_rows]
    if missing or unknown:
        sys.exit(f"in no batch: {missing}\nnot an open row: {unknown}")

    out = [
        "# Backlog, sorted into batches",
        "",
        f"Every open row of `docs/BACKLOG.md` ({len(open_rows)} on 2026-11-16), each in exactly one batch: rows that share files, a",
        "design decision or a review round, so that they are cheaper done together. The backlog stays the source: a row's",
        "full text and status are there; this file only groups the ids. `U` marks a row that came from the user. Sizes are",
        "the lead's estimate (S: hours, M: a day or two, L: several days or a brief first), not measured.",
        "",
        "Written by `python3 tools/backlog-batches.py .`, which holds the batches and fails when an open row is in no",
        "batch or in two: give a new row its batch there, then run it again.",
        "",
        "| Section | Batch | Rows | Size |",
        "|---|---|---|---|",
    ]
    for section, batches in B:
        for title, _, size, _, ids in batches:
            out.append(f"| {section.split('.')[0]} | {title} | {len(ids.split())} | {size} |")
    for section, batches in B:
        out += ["", f"## {section}"]
        for title, shares, size, needs, ids in batches:
            out += ["", f"### {title}", "", f"Shares: {shares}. Size: {size}. Needs you: {needs}.", "", "| Row | | What |", "|---|---|---|"]
            for i in ids.split():
                text, user, _ = open_rows[i]
                out.append(f"| {i} | {'U' if user else ''} | {text} |")
    open(f"{ROOT}/docs/BACKLOG-BATCHES.md", "w").write("\n".join(out) + "\n")
    print(f"{len(open_rows)} rows, {sum(len(b) for _, b in B)} batches")


main()
