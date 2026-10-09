# UX briefs

One brief per user-facing feature (CLAUDE.md "UX bar"). A feature is done when it meets its brief's definition of
done, not when it works — and the brief asks what the feature can *become* and what it combines with, not
only its minimum job. Briefs are researched (other shells' approaches, cited) and written before or with the
feature's cards; cards cite them; the lead reviews screenshots against them.

## Template
```
# <Feature> — UX brief
Status: draft | agreed | implemented (functional) | done (UX)

## Job
What the user wants from it, in one or two sentences; where it lives (bar / Island face / Stage card / quick
settings / Settings page / keyboard) and how it relates to the rest of the shell.

## References (what others do, cited)
Per shell: the patterns worth knowing, with URLs.

## Beyond the basic job
What it *can* become: the extended version and how it uses its space; what it combines with (other modules that
feed it or that it feeds — `COMPOSITION.md`), which of those are core and which are mod contributions to a slot;
what makes it pleasant (glanceable summary, one-step actions, delight that stays calm).

## Design
Layout per surface (compact → peek → expanded), content, interactions (pointer, keyboard, scroll), motion
(DESIGN-SYSTEM §9), copy (i18n keys).

## States
default · empty · loading · error · offline/stale · unavailable (service/hardware) · forced/inert (Nix, policy) ·
many items · tiny/huge outputs · several outputs · ja copy length.

## Fit and constraints
Ma (what runs while hidden: nothing), Shōjiki (what is shown when unknown), budgets (per-output PSS, idle frames),
daemon vs view responsibilities, contracts touched.

## Definition of done
Checklist the lead verifies with screenshots/tests.

## Later
Ideas deliberately left out, each a BACKLOG row.
```

## Briefs
| Feature | Brief | Status |
|---|---|---|
| Composition map (which modules feed which views) | [COMPOSITION.md](COMPOSITION.md) | draft |
| Quick settings | [quick-settings.md](quick-settings.md) | draft (research running) |
| Island + expanded views + OSD | [island.md](island.md) | draft (research running) |
| Settings app, mods, pickers | [settings.md](settings.md) | draft (research running) |
| Wallpaper mod | [wallpaper.md](wallpaper.md) | draft (research running) |
| System monitor mod | [sysmon.md](sysmon.md) | draft (research running) |
| Weather mod | [weather.md](weather.md) | draft (research running) |
