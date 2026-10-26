use super::*;

fn strings(v: &[&str]) -> Vec<String> {
    v.iter().map(|s| (*s).to_string()).collect()
}

fn globals() -> Globals {
    Globals {
        draw: Draw::Dynamic,
        reveal_delay_ms: 250,
        gap: 8,
        join_radius: 16,
        bar_size: 32,
    }
}

fn top_zones(end: &[&str]) -> [Vec<String>; 3] {
    [
        strings(&["sidebar_left", "workspaces", "windows"]),
        strings(&["island"]),
        strings(end),
    ]
}

const TOP_END: [&str; 8] = [
    "volume",
    "mods",
    "recorder",
    "keyboard",
    "clock",
    "quick",
    "tray",
    "sidebar_right",
];

/// The schema defaults: one top bar with today's modules, no frame, dynamic everywhere.
fn defaults() -> OutputConfig {
    let mut top = EdgeConfig::empty();
    top.bar = true;
    top.zones = top_zones(&TOP_END);
    OutputConfig {
        bar_size: 32,
        frame: FrameConfig {
            enabled: false,
            thickness: 8,
            radius: 16,
            reserve: true,
        },
        edges: [
            top,
            EdgeConfig::empty(),
            EdgeConfig::empty(),
            EdgeConfig::empty(),
        ],
        dock: DockConfig {
            enabled: false,
            edge: Edge::Bottom,
            visibility: Visibility::EmptyDesktop,
            reserve: Reserve::Auto,
            draw: None,
            size: 60,
        },
        sidebar_right: SidebarConfig {
            width: 420,
            visibility: Visibility::Hidden,
            reserve: Reserve::Auto,
            draw: None,
        },
        sidebar_left: SidebarConfig {
            width: 420,
            visibility: Visibility::Hidden,
            reserve: Reserve::Auto,
            draw: None,
        },
        island_draw: None,
    }
}

fn widget_mod(id: &str, enabled: bool, widgets: &[&str]) -> ModWidgets {
    ModWidgets {
        id: id.into(),
        enabled,
        widgets: strings(widgets),
    }
}

fn lay(cfg: &OutputConfig, mods: &[ModWidgets]) -> OutputLayout {
    output(&globals(), mods, cfg)
}

fn ids(z: &[Module]) -> Vec<&str> {
    z.iter().map(|m| m.id.as_str()).collect()
}

// --- the fixture ------------------------------------------------------------------------------------------------

/// The inputs `snap_runtime_layout.json`'s `"*"` entry describes: the dock on, floating by the user's choice, a timer
/// glance on the bottom edge shown on hover, the left sidebar 380 px and on hover.
fn fixture_star() -> OutputConfig {
    let mut c = defaults();
    c.edges[1].visibility = Visibility::Hover;
    c.edges[1].zones[1] = strings(&["mod:timer:timer"]);
    c.dock.enabled = true;
    c.dock.draw = Some(Draw::Floating);
    c.sidebar_left.width = 380;
    c.sidebar_left.visibility = Visibility::Hover;
    c
}

/// `DP-1`: the same with the frame on, sysmon named instead of `mods` (so weather's glance is unplaced) and a typo.
fn fixture_dp1() -> OutputConfig {
    let mut c = fixture_star();
    c.frame.enabled = true;
    c.edges[0].zones = top_zones(&[
        "volume",
        "mod:sysmon:sysmon",
        "recorder",
        "keyboard",
        "clok",
        "clock",
        "quick",
        "tray",
        "sidebar_right",
    ]);
    c
}

#[test]
fn the_fixture_comes_out_byte_equal() {
    // One mod set for every output (row 480): `"*"` keeps the default zones, so `mods` brings sysmon and weather into the
    // top bar's end; DP-1 names its zones without `mods`, so weather is offered back as unplaced.
    let mods = [
        widget_mod("sysmon", true, &["sysmon"]),
        widget_mod("timer", true, &["timer"]),
        widget_mod("weather", true, &["weather"]),
    ];
    let g = globals();
    let doc = Document {
        draw: g.draw,
        reveal_delay_ms: g.reveal_delay_ms,
        gap: g.gap,
        join_radius: g.join_radius,
        bar_size: g.bar_size,
        outputs: BTreeMap::from([
            ("*".to_string(), output(&g, &mods, &fixture_star())),
            ("DP-1".to_string(), output(&g, &mods, &fixture_dp1())),
        ]),
    };
    let got = format!(
        r#"{{"t":"snap","doc":"runtime.layout","rev":3,"data":{}}}"#,
        serde_json::to_string(&doc).unwrap()
    );
    let want = include_str!("../../../fixtures/ipc/server/snap_runtime_layout.json").trim_end();
    assert_eq!(got, want);
}

#[test]
fn compute_lays_out_every_output_and_the_wildcard() {
    let input = Input {
        globals: globals(),
        mods: vec![],
        outputs: BTreeMap::from([
            ("*".to_string(), defaults()),
            ("HDMI-A-1".to_string(), fixture_dp1()),
        ]),
    };
    let doc = compute(&input);
    assert_eq!(doc.outputs.len(), 2);
    assert!(!doc.outputs["*"].frame.on);
    assert!(doc.outputs["HDMI-A-1"].frame.on);
    let v = doc.to_value();
    assert_eq!(v["outputs"]["*"]["edges"]["top"]["holder"], "bar");
}

// --- frame --------------------------------------------------------------------------------------------------------

#[test]
fn frame_off_has_no_band_and_frame_on_bands_every_edge_but_a_docked_bars() {
    let off = lay(&defaults(), &[]);
    assert_eq!(off.frame.band, PerEdge::of(|_| 0));
    assert_eq!(off.edges.left.reserve, 0);
    assert_eq!(off.edges.left.holder, Holder::None);

    let mut c = defaults();
    c.frame.enabled = true;
    let on = lay(&c, &[]);
    assert_eq!(
        on.frame.band,
        PerEdge {
            top: 0,
            bottom: 8,
            left: 8,
            right: 8
        }
    );
    // The docked top bar carries its edge's strip and holds the zone there (row 510); the frame holds the rest.
    assert_eq!(on.edges.top.holder, Holder::Bar);
    for e in [Edge::Bottom, Edge::Left, Edge::Right] {
        assert_eq!(on.edge(e).holder, Holder::Frame, "{e:?}");
    }
    assert_eq!(on.edges.top.reserve, 32);
    assert_eq!(on.edges.bottom.reserve, 8);
    assert_eq!(on.edges.bottom.inset, 8);

    // A frame that keeps no space: the bar holds its edge, the bands nothing.
    c.frame.reserve = false;
    let loose = lay(&c, &[]);
    assert_eq!(loose.edges.top.holder, Holder::Bar);
    assert_eq!(loose.edges.bottom.holder, Holder::None);
    assert_eq!(loose.edges.bottom.reserve, 0);
    assert_eq!(loose.frame.band.bottom, 8);
}

// --- bars ---------------------------------------------------------------------------------------------------------

#[test]
fn a_bar_on_each_edge() {
    for e in Edge::ALL {
        let mut c = defaults();
        let zones = c.edges[0].zones.clone();
        c.edges[0] = EdgeConfig::empty();
        c.edges[e.index()].bar = true;
        c.edges[e.index()].zones = zones;
        let l = lay(&c, &[]);
        for o in Edge::ALL {
            let el = l.edge(o);
            assert_eq!(el.bar, o == e, "{e:?}/{o:?}");
            assert_eq!(el.size, (o == e).then_some(32));
            assert_eq!(el.reserve, if o == e { 32 } else { 0 });
            assert_eq!(el.holder, if o == e { Holder::Bar } else { Holder::None });
        }
        let island = l.island.expect("the island is placed");
        assert_eq!(
            (island.edge, island.zone, island.host),
            (e.name(), "center", "bar")
        );
    }
}

#[test]
fn bars_on_several_edges_each_hold_their_own() {
    let mut c = defaults();
    c.edges[1].bar = true;
    c.edges[2].bar = true;
    c.edges[2].zones[0] = strings(&["clock"]);
    let l = lay(&c, &[]);
    assert_eq!(l.edges.top.holder, Holder::Bar);
    assert_eq!(l.edges.bottom.holder, Holder::Bar);
    assert_eq!(l.edges.left.holder, Holder::Bar);
    assert_eq!(l.edges.right.holder, Holder::None);
    assert_eq!(ids(&l.edges.left.zones.start), ["clock"]);
    // Sidebars run between the top and the bottom bar.
    assert_eq!(l.sidebars.right.span, Span { start: 32, end: 32 });
    assert_eq!(
        l.sidebars.right.joins,
        Some(Joins {
            start: "bar:top".into(),
            end: "bar:bottom".into()
        })
    );
    // The left sidebar stands on the left bar.
    assert_eq!(l.sidebars.left.inset, 32);
}

#[test]
fn a_bar_in_every_draw_mode() {
    for frame in [false, true] {
        for draw in [Draw::Floating, Draw::Dynamic, Draw::Connected] {
            let mut c = defaults();
            c.frame.enabled = frame;
            c.edges[0].draw = Some(draw);
            let l = lay(&c, &[]);
            let top = &l.edges.top;
            assert_eq!((top.draw, top.draw_source), (draw, Source::Set));
            let band = if frame { 8 } else { 0 };
            match draw {
                Draw::Floating => {
                    // Off the band (which shows under a floating bar) by a gap.
                    assert_eq!(top.inset, band + 8);
                    assert_eq!(top.reserve, band + 8 + 32);
                    assert_eq!(l.frame.band.top, band);
                    // Under a floating bar a sidebar starts a gap below it and meets nothing there (I253 (a)).
                    assert_eq!(l.sidebars.right.span.start, band + 8 + 32 + 8);
                    assert_eq!(l.sidebars.right.joins.as_ref().unwrap().start, "none");
                }
                _ => {
                    assert_eq!(top.inset, 0);
                    assert_eq!(top.reserve, 32);
                    assert_eq!(l.frame.band.top, 0);
                    assert_eq!(l.sidebars.right.span.start, 32);
                }
            }
        }
    }
}

#[test]
fn the_preset_drives_every_auto_component() {
    for preset in [Draw::Floating, Draw::Dynamic, Draw::Connected] {
        let mut g = globals();
        g.draw = preset;
        let mut c = defaults();
        c.dock.enabled = true;
        c.edges[1].zones[1] = strings(&["clock"]);
        let l = output(&g, &[], &c);
        assert_eq!(
            (l.edges.top.draw, l.edges.top.draw_source),
            (preset, Source::Auto)
        );
        assert_eq!(l.edges.bottom.draw, preset);
        assert_eq!((l.dock.draw, l.dock.draw_source), (preset, Source::Auto));
        assert_eq!(l.sidebars.right.draw, preset);
        assert_eq!(l.sidebars.left.draw, preset);
        assert_eq!(l.island.as_ref().unwrap().draw, preset);
    }
}

// --- dock, sidebars, island -----------------------------------------------------------------------------------------

#[test]
fn the_dock_in_every_draw_mode() {
    for draw in [Draw::Floating, Draw::Dynamic, Draw::Connected] {
        for frame in [false, true] {
            let mut c = defaults();
            c.dock.enabled = true;
            c.dock.draw = Some(draw);
            c.frame.enabled = frame;
            let d = lay(&c, &[]).dock;
            let band = if frame { 8 } else { 0 };
            match draw {
                Draw::Floating => {
                    assert_eq!(d.inset, band + 8);
                    assert_eq!(d.joins, None);
                    assert_eq!(d.radius, 0);
                }
                Draw::Dynamic => {
                    assert_eq!(d.inset, band);
                    assert_eq!(
                        d.joins.as_deref(),
                        Some(if frame { "frame" } else { "edge" })
                    );
                    assert_eq!(d.radius, 16);
                }
                Draw::Connected => {
                    assert_eq!(d.inset, band);
                    assert_eq!(d.radius, 0);
                }
            }
        }
    }
    // On a bottom bar: it sits on the bar.
    let mut c = defaults();
    c.dock.enabled = true;
    c.edges[1].bar = true;
    let d = lay(&c, &[]).dock;
    assert_eq!((d.inset, d.joins.as_deref()), (32, Some("bar:bottom")));
}

#[test]
fn sidebars_in_every_draw_mode() {
    for draw in [Draw::Floating, Draw::Dynamic, Draw::Connected] {
        let mut c = defaults();
        c.frame.enabled = true;
        c.sidebar_right.draw = Some(draw);
        let s = lay(&c, &[]).sidebars.right;
        match draw {
            Draw::Floating => {
                assert_eq!(s.inset, 16);
                assert_eq!(s.span, Span { start: 40, end: 16 });
                assert_eq!(s.joins, None);
                assert_eq!(s.radius, 0);
            }
            _ => {
                assert_eq!(s.inset, 8);
                assert_eq!(s.span, Span { start: 32, end: 8 });
                assert_eq!(
                    s.joins,
                    Some(Joins {
                        start: "bar:top".into(),
                        end: "frame".into()
                    })
                );
                assert_eq!(s.radius, if draw == Draw::Dynamic { 16 } else { 0 });
            }
        }
    }
}

#[test]
fn a_floating_sidebar_under_a_floating_bar_keeps_a_gap_from_it() {
    let mut c = defaults();
    c.edges[0].draw = Some(Draw::Floating);
    c.sidebar_right.draw = Some(Draw::Floating);
    let s = lay(&c, &[]).sidebars.right;
    // The bar: inset gap, 32 deep; the sidebar a gap below it, never over its end.
    assert_eq!(s.span.start, 8 + 32 + 8);
    assert_eq!(s.joins, None);
    // A hidden floating bar comes out over the column: the column reaches the band.
    c.edges[0].visibility = Visibility::Hidden;
    assert_eq!(lay(&c, &[]).sidebars.right.span.start, 8);
}

#[test]
fn the_island_follows_its_zone_and_is_absent_when_no_zone_names_it() {
    let mut c = defaults();
    c.edges[0].zones[1].clear();
    c.edges[1].zones[2] = strings(&["island"]);
    c.island_draw = Some(Draw::Connected);
    let l = lay(&c, &[]);
    let i = l.island.unwrap();
    assert_eq!((i.edge, i.zone, i.host), ("bottom", "end", "module"));
    assert_eq!((i.draw, i.draw_source), (Draw::Connected, Source::Set));

    c.edges[1].zones[2].clear();
    let l = lay(&c, &[]);
    assert!(l.island.is_none());
    assert!(serde_json::to_value(&l).unwrap().get("island").is_none());
    assert!(l.unplaced.iter().any(|u| u.module.id == "island"));
}

// --- reserve × visibility ---------------------------------------------------------------------------------------------

#[test]
fn reserve_follows_visibility() {
    use Reserve::*;
    use Visibility::*;
    let cases = [
        (Always, Auto, 32, false),
        (Always, On, 32, false),
        (Always, Off, 0, false),
        (Hover, Auto, 0, false),
        (Hover, On, 32, false),
        (Hover, Off, 0, false),
        (EmptyDesktop, Auto, 0, false),
        (EmptyDesktop, On, 32, false),
        (Hidden, Auto, 0, true),
        (Hidden, On, 0, true),
        (Hidden, Off, 0, true),
    ];
    for (vis, res, want, inert) in cases {
        let mut c = defaults();
        c.edges[0].visibility = vis;
        c.edges[0].reserve = res;
        let top = lay(&c, &[]).edges.top;
        assert_eq!(top.reserve, want, "{vis:?} {res:?}");
        assert_eq!(top.reserve_reason.is_some(), inert, "{vis:?} {res:?}");
        assert_eq!(
            top.reserve_source,
            if res == Auto {
                Source::Auto
            } else {
                Source::Set
            }
        );
        assert_eq!(
            top.holder,
            if want > 0 { Holder::Bar } else { Holder::None }
        );

        // The dock and the sidebars keep space by the same rule.
        let mut c = defaults();
        c.dock.enabled = true;
        c.dock.visibility = vis;
        c.dock.reserve = res;
        c.sidebar_right.visibility = vis;
        c.sidebar_right.reserve = res;
        let l = lay(&c, &[]);
        assert_eq!(l.dock.reserve > 0, want > 0, "dock {vis:?} {res:?}");
        assert_eq!(
            l.sidebars.right.reserve > 0,
            want > 0,
            "sidebar {vis:?} {res:?}"
        );
        assert_eq!(l.sidebars.right.reserve_reason.is_some(), inert);
        if want > 0 {
            assert_eq!(l.edges.bottom.holder, Holder::Dock);
            assert_eq!(l.edges.bottom.reserve, l.dock.reserve);
            assert_eq!(l.edges.right.holder, Holder::Sidebar);
            assert_eq!(l.edges.right.reserve, 420);
        }
    }
}

#[test]
fn a_hidden_bar_is_not_the_band_and_a_hover_bar_is() {
    let mut c = defaults();
    c.frame.enabled = true;
    // A hidden bar: the frame bands its edge and holds it; the bar comes out over the band.
    c.edges[0].visibility = Visibility::Hidden;
    let hidden = lay(&c, &[]);
    assert_eq!(hidden.frame.band.top, 8);
    assert_eq!(hidden.edges.top.holder, Holder::Frame);
    assert_eq!(hidden.edges.top.reserve, 8);
    // A hover bar stays the band; the zone keeps the frame's thickness while the bar is in.
    c.edges[0].visibility = Visibility::Hover;
    let hover = lay(&c, &[]);
    assert_eq!(hover.frame.band.top, 0);
    assert_eq!(hover.edges.top.holder, Holder::Bar);
    assert_eq!(hover.edges.top.reserve, 8);
}

#[test]
fn a_side_bar_runs_between_the_horizontal_bars() {
    let mut c = defaults();
    c.edges[2].bar = true;
    let l = lay(&c, &[]);
    // Under the top bar, down to the screen edge; the horizontal bars carry no span.
    assert_eq!(l.edges.left.span, Some(Span { start: 32, end: 0 }));
    assert_eq!(l.edges.top.span, None);
    assert_eq!(l.edges.right.span, None);
    // A bottom bar too; a hidden one leaves the side bar the edge's band.
    c.edges[1].bar = true;
    assert_eq!(
        lay(&c, &[]).edges.left.span,
        Some(Span { start: 32, end: 32 })
    );
    c.edges[1].visibility = Visibility::Hidden;
    c.frame.enabled = true;
    assert_eq!(
        lay(&c, &[]).edges.left.span,
        Some(Span { start: 32, end: 8 })
    );
    // A floating top bar stands off its edge; a floating side bar keeps a gap from it.
    c.edges[0].draw = Some(Draw::Floating);
    c.edges[2].draw = Some(Draw::Floating);
    let f = lay(&c, &[]);
    assert_eq!(f.edges.top.inset, 16);
    assert_eq!(
        f.edges.left.span,
        Some(Span {
            start: 16 + 32 + 8,
            end: 8 + 8
        })
    );
}

#[test]
fn holder_order_is_frame_bar_dock_sidebar_module_none() {
    // Bottom: a bar, the dock and modules all keep space — the bar holds it, the zone is the widest.
    let mut c = defaults();
    c.edges[1].bar = true;
    c.dock.enabled = true;
    c.dock.visibility = Visibility::Always;
    let l = lay(&c, &[]);
    assert_eq!(l.edges.bottom.holder, Holder::Bar);
    assert_eq!(l.edges.bottom.reserve, l.dock.reserve);
    assert!(l.dock.reserve > 32);
    // The frame beats them all, but for a docked bar: it carries the edge's strip and holds the zone (row 510).
    c.frame.enabled = true;
    assert_eq!(lay(&c, &[]).edges.bottom.holder, Holder::Bar);
    c.edges[1].draw = Some(Draw::Floating);
    assert_eq!(lay(&c, &[]).edges.bottom.holder, Holder::Frame);
    c.edges[1].draw = None;
    // Without the bar the dock holds it.
    c.frame.enabled = false;
    c.edges[1].bar = false;
    assert_eq!(lay(&c, &[]).edges.bottom.holder, Holder::Dock);
    // A right sidebar pinned open beats a module group on its edge.
    let mut c = defaults();
    c.sidebar_right.visibility = Visibility::Always;
    c.edges[3].zones[0] = strings(&["clock"]);
    assert_eq!(lay(&c, &[]).edges.right.holder, Holder::Sidebar);
    // Alone, an always-shown module group holds its edge.
    c.sidebar_right.visibility = Visibility::Hidden;
    let l = lay(&c, &[]);
    assert_eq!(l.edges.right.holder, Holder::Module);
    assert_eq!(l.edges.right.reserve, 32);
}

// --- zones ----------------------------------------------------------------------------------------------------------

#[test]
fn mods_expands_to_the_enabled_widgets_no_zone_names_in_mod_order() {
    let mods = [
        widget_mod("ai", false, &["ai"]),
        widget_mod("sysmon", true, &["cpu", "mem"]),
        widget_mod("timer", true, &["timer"]),
        widget_mod("weather", true, &["weather"]),
    ];
    let mut c = defaults();
    c.edges[1].zones[1] = strings(&["mod:timer:timer"]);
    let l = lay(&c, &mods);
    assert_eq!(
        ids(&l.edges.top.zones.end),
        [
            "volume",
            "mod:sysmon:cpu",
            "mod:sysmon:mem",
            "mod:weather:weather",
            "recorder",
            "keyboard",
            "clock",
            "quick",
            "tray",
            "sidebar_right"
        ]
    );
    let w = &l.edges.top.zones.end[3];
    assert_eq!(
        (w.kind, w.mod_id.as_deref(), w.provide.as_deref()),
        (Kind::Mod, Some("weather"), Some("widget:weather"))
    );
    // Something holds `mods`: nothing is unplaced.
    assert!(l.unplaced.is_empty());
}

#[test]
fn problems_name_what_a_zone_cannot_draw() {
    let mods = [
        widget_mod("ai", false, &["ai"]),
        widget_mod("calendar", true, &[]),
    ];
    let mut c = defaults();
    c.edges[2].zones[0] = strings(&[
        "clok",
        "mod:ai:ai",
        "mod:calendar:calendar",
        "mod:nope:x",
        "mod:broken",
    ]);
    let l = lay(&c, &mods);
    assert!(l.edges.left.zones.start.is_empty());
    let got: Vec<(&str, &str, &str)> = l
        .problems
        .iter()
        .map(|p| (p.id.as_str(), p.zone.as_str(), p.reason))
        .collect();
    assert_eq!(
        got,
        [
            ("clok", "edges.left.start", REASON_UNKNOWN),
            ("mod:ai:ai", "edges.left.start", REASON_MOD_OFF),
            (
                "mod:calendar:calendar",
                "edges.left.start",
                REASON_NO_GLANCE
            ),
            ("mod:nope:x", "edges.left.start", REASON_UNKNOWN),
            ("mod:broken", "edges.left.start", REASON_UNKNOWN),
        ]
    );
    // The edge's only entries could not be drawn: it shows no module group, so it keeps no space.
    assert_eq!(l.edges.left.reserve, 0);
}

#[test]
fn unplaced_lists_enabled_modules_with_a_glance_no_zone_shows() {
    let mods = [
        widget_mod("calendar", true, &[]),
        widget_mod("off", false, &["w"]),
        widget_mod("sysmon", true, &["sysmon"]),
    ];
    let mut c = defaults();
    c.edges[0].zones = top_zones(&["volume", "clock"]);
    let l = lay(&c, &mods);
    let got: Vec<(&str, &str)> = l
        .unplaced
        .iter()
        .map(|u| (u.module.id.as_str(), u.reason))
        .collect();
    // Core modules first (K72 order), then the mods' glances; a mod without a glance or that is off is never unplaced.
    assert_eq!(
        got,
        [
            ("recorder", REASON_NOT_LISTED),
            ("keyboard", REASON_NOT_LISTED),
            ("quick", REASON_NOT_LISTED),
            ("tray", REASON_NOT_LISTED),
            ("sidebar_right", REASON_NOT_LISTED),
            ("mod:sysmon:sysmon", REASON_NOT_LISTED),
        ]
    );
    let v = serde_json::to_value(&l.unplaced[5]).unwrap();
    assert_eq!(
        v,
        serde_json::json!({"id": "mod:sysmon:sysmon", "kind": "mod", "mod": "sysmon", "provide": "widget:sysmon",
                           "reason": REASON_NOT_LISTED})
    );
}

#[test]
fn an_edge_without_a_bar_shows_its_zones_as_module_groups() {
    let mut c = defaults();
    c.frame.enabled = true;
    c.edges[1].zones[1] = strings(&["clock"]);
    for (draw, inset) in [
        (Draw::Dynamic, 8),
        (Draw::Connected, 8),
        (Draw::Floating, 16),
    ] {
        c.edges[1].draw = Some(draw);
        let b = lay(&c, &[]).edges.bottom;
        assert!(!b.bar);
        assert_eq!(b.size, None);
        assert_eq!(b.inset, inset);
        assert_eq!(ids(&b.zones.center), ["clock"]);
    }
    // Shown always without the frame: it keeps its own space and holds the edge.
    c.frame.enabled = false;
    c.edges[1].draw = None;
    let b = lay(&c, &[]).edges.bottom;
    assert_eq!((b.reserve, b.holder), (32, Holder::Module));
}

#[test]
fn the_wildcard_serialises_without_null() {
    let doc = compute(&Input {
        globals: globals(),
        mods: vec![],
        outputs: BTreeMap::from([("*".to_string(), defaults())]),
    });
    let text = serde_json::to_string(&doc).unwrap();
    assert!(!text.contains("null"), "{text}");
}

#[test]
fn parsers_read_the_config_spelling() {
    assert_eq!(Draw::parse("auto"), None);
    assert_eq!(Draw::parse("connected"), Some(Draw::Connected));
    assert_eq!(
        Visibility::parse("empty_desktop"),
        Some(Visibility::EmptyDesktop)
    );
    assert_eq!(Reserve::parse("off"), Some(Reserve::Off));
    assert_eq!(Edge::parse("left"), Some(Edge::Left));
    assert_eq!(Edge::parse("middle"), None);
}
