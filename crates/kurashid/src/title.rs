//! Title bars on Stage cards (W53.0b, K80, `docs/ux/styles.md` "Decided" 3). Where the style draws a title bar (its
//! `decor.title` token names one) and `title_bar.buttons` is not `off`, `runtime.ui` carries `title` for the open card:
//! the buttons it draws and what each does, resolved here (rule 1) from `title_bar.{close,maximize,minimize}`.
//! Shōjiki: a button whose action is `none` is not drawn, and `app_menu` names the menu it opens or says `hide`.
//! - `close`, `hide`: the card closes (a Stage card has no minimized state: hiding it is going back to the island).
//! - `full_screen`: the card grows to the largest size its output has room for (`title.full`); again: back to its size.
//! - `app_menu`: the tray menu of the app the card belongs to — today the media card's player, when the tray lists an
//!   item of the same name with a menu; every other card hides.
//!
//! Action `ui.title {button}` presses one. `runtime.ui.full` (`"<panel>:<face>"`) keeps which card is full screen; it
//! does not outlive the card (another panel is another key; `ui.close` drops it).

use std::sync::Arc;

use serde_json::{Value, json};

use crate::actions::{ActionError, ActionRegistry};
use crate::config::ConfigStore;
use crate::hub::Hub;

pub const DOC: &str = "runtime.ui";
/// The theme token naming the style's title bar component (the look's `[slots] title`, W53.0a); `""` = none.
pub const TOKEN: &str = "decor.title";
/// `ui.title` of a button the open card does not draw.
pub const NO_BUTTON: &str = "ui.error.no_title_button";
/// The buttons in the order a title bar draws them.
pub const BUTTONS: [&str; 3] = ["minimize", "maximize", "close"];

/// The config the title bar follows.
#[derive(Debug, Clone, PartialEq)]
pub struct Settings {
    /// `off` | `close` | `full`.
    pub buttons: String,
    pub close: String,
    pub maximize: String,
    pub minimize: String,
}

impl Settings {
    pub fn read(store: &ConfigStore) -> Self {
        let s = |k: &str| crate::theme::s(store, k);
        Self {
            buttons: s("title_bar.buttons"),
            close: s("title_bar.close"),
            maximize: s("title_bar.maximize"),
            minimize: s("title_bar.minimize"),
        }
    }

    fn action(&self, button: &str) -> &str {
        match button {
            "close" => &self.close,
            "maximize" => &self.maximize,
            "minimize" => &self.minimize,
            _ => "none",
        }
    }

    fn draws(&self, button: &str) -> bool {
        match self.buttons.as_str() {
            "full" => true,
            "close" => button == "close",
            _ => false,
        }
    }
}

/// The open card's key: `"<panel>:<face>"`, `None` while no card is open.
pub fn card_key(ui: &Value) -> Option<String> {
    let panel = ui["panel"].as_str().filter(|p| !p.is_empty())?;
    Some(format!("{panel}:{}", ui["face"].as_str().unwrap_or("")))
}

/// The tray item (with a menu) of the app the open card belongs to: the media card's player.
pub fn app_menu(ui: &Value, media: &Value, tray: &Value) -> Option<String> {
    if ui["panel"] != "island" || ui["face"] != "media" {
        return None;
    }
    let player = media["player"].as_str()?.to_lowercase();
    if player.is_empty() {
        return None;
    }
    let player = player.rsplit('.').next().unwrap_or(&player).to_owned();
    tray["items"].as_array()?.iter().find_map(|it| {
        if it["has_menu"] != true {
            return None;
        }
        let id = it["id"].as_str()?;
        let names = [id, it["title"].as_str().unwrap_or("")].map(str::to_lowercase);
        names
            .iter()
            .any(|n| !n.is_empty() && (n.contains(&player) || player.contains(n.as_str())))
            .then(|| id.to_owned())
    })
}

/// What one button does on the open card: `(action, menu)`; `None` when it is not drawn.
fn resolve(
    settings: &Settings,
    button: &str,
    menu: Option<&str>,
) -> Option<(&'static str, Option<String>)> {
    if !settings.draws(button) {
        return None;
    }
    Some(match settings.action(button) {
        "close" => ("close", None),
        "hide" => ("hide", None),
        "full_screen" => ("full_screen", None),
        "app_menu" => match menu {
            Some(id) => ("app_menu", Some(id.to_owned())),
            None => ("hide", None),
        },
        _ => return None,
    })
}

/// `runtime.ui.title` for the open card, `None` when no title bar is drawn.
pub fn title_of(
    settings: &Settings,
    style_title: bool,
    ui: &Value,
    menu: Option<&str>,
) -> Option<Value> {
    let key = card_key(ui)?;
    if !style_title || ui["polkit"] == true {
        return None;
    }
    let buttons: Vec<Value> = BUTTONS
        .iter()
        .filter_map(|b| {
            let (action, menu) = resolve(settings, b, menu)?;
            let mut v = json!({"id": b, "action": action});
            if let Some(m) = menu {
                v["menu"] = json!(m);
            }
            Some(v)
        })
        .collect();
    if settings.buttons == "off" {
        return None;
    }
    Some(json!({"buttons": buttons, "full": ui["full"].as_str() == Some(key.as_str())}))
}

/// Presses `button` on the open card: the change to `runtime.ui`, or why not.
pub fn press(
    settings: &Settings,
    ui: &mut Value,
    button: &str,
    menu: Option<&str>,
) -> Result<(), &'static str> {
    let key = card_key(ui).ok_or(NO_BUTTON)?;
    let (action, menu) = resolve(settings, button, menu).ok_or(NO_BUTTON)?;
    match action {
        "full_screen" => {
            let on = ui["full"].as_str() == Some(key.as_str());
            if on {
                if let Some(o) = ui.as_object_mut() {
                    o.remove("full");
                }
            } else {
                ui["full"] = json!(key);
            }
        }
        "app_menu" => {
            let id = menu.unwrap_or_default();
            ui["panel"] = json!("tray");
            ui["popup"] = json!(true);
            ui["tray"] = json!(id);
            ui["face"] = json!("");
            ui["launcher"] = json!(false);
            if let Some(o) = ui.as_object_mut() {
                o.remove("full");
                o.remove("peek");
            }
        }
        _ => {
            crate::wiring::close_panel(ui);
            if let Some(o) = ui.as_object_mut() {
                o.remove("full");
            }
        }
    }
    Ok(())
}

/// A `runtime.ui` patch that touches only the peek or the title overlay.
fn only_peek_or_title(ops: &Value) -> bool {
    ops.as_object()
        .is_some_and(|o| o.keys().all(|k| k == "peek" || k == "title"))
}

struct Title {
    hub: Arc<Hub>,
    store: Option<Arc<ConfigStore>>,
}

impl Title {
    fn settings(&self) -> Settings {
        self.store
            .as_deref()
            .map(Settings::read)
            .unwrap_or(Settings {
                buttons: "full".into(),
                close: "close".into(),
                maximize: "full_screen".into(),
                minimize: "app_menu".into(),
            })
    }

    fn snap(&self, doc: &str) -> Value {
        self.hub
            .snapshot(doc)
            .map(|(_, d)| d)
            .unwrap_or(Value::Null)
    }

    fn style_title(&self) -> bool {
        self.snap(crate::theme::DOC)["tokens"][TOKEN]
            .as_str()
            .is_some_and(|t| !t.is_empty())
    }

    fn menu(&self, ui: &Value) -> Option<String> {
        app_menu(ui, &self.snap("svc.media"), &self.snap("svc.tray"))
    }

    fn refresh(&self) {
        let ui = self.snap(DOC);
        let title = title_of(
            &self.settings(),
            self.style_title(),
            &ui,
            self.menu(&ui).as_deref(),
        );
        let _ = self.hub.set_overlay(DOC, "title", title);
    }
}

/// Keeps `runtime.ui.title` current and registers `ui.title {button}`.
pub fn register(hub: &Arc<Hub>, store: Option<Arc<ConfigStore>>, actions: &mut ActionRegistry) {
    let t = Arc::new(Title {
        hub: hub.clone(),
        store: store.clone(),
    });
    t.refresh();
    if let Some(store) = &store {
        let t = t.clone();
        store.on_change(move |_| t.refresh());
    }
    let tt = t.clone();
    actions.register("ui.title", "action.ui.title", move |a| {
        let t = tt.clone();
        async move {
            let button = a["button"]
                .as_str()
                .ok_or_else(|| ActionError::Invalid(crate::wiring::ARGS_INVALID.into()))?
                .to_owned();
            let settings = t.settings();
            let ui = t.snap(DOC);
            let menu = t.menu(&ui);
            let mut refused = None;
            t.hub
                .update(DOC, None, |d| {
                    if let Err(e) = press(&settings, d, &button, menu.as_deref()) {
                        refused = Some(e);
                    }
                })
                .map_err(|e| ActionError::Internal(e.to_string()))?;
            match refused {
                Some(e) => Err(ActionError::Invalid(e.into())),
                None => Ok(None),
            }
        }
    });
    actions.describe("ui.title", "{button}");
    if let Ok(rt) = tokio::runtime::Handle::try_current() {
        let mut events = hub.events();
        rt.spawn(async move {
            loop {
                match events.recv().await {
                    Ok(msg) => match msg.as_ref() {
                        // A peek (a hover sweep over the bar) and our own overlay change nothing here.
                        kurashi_ipc::ServerMsg::Patch { doc, ops, .. }
                            if doc == DOC && only_peek_or_title(ops) =>
                        {
                            continue;
                        }
                        // The player and the tray matter only while the media card is open.
                        kurashi_ipc::ServerMsg::Snap { doc, .. }
                        | kurashi_ipc::ServerMsg::Patch { doc, .. }
                            if doc == "svc.tray" || doc == "svc.media" =>
                        {
                            if t.snap(DOC)["face"] != "media" {
                                continue;
                            }
                        }
                        kurashi_ipc::ServerMsg::Snap { doc, .. }
                        | kurashi_ipc::ServerMsg::Patch { doc, .. }
                            if doc == DOC || doc == crate::theme::DOC => {}
                        _ => continue,
                    },
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                }
                t.refresh();
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn settings(buttons: &str) -> Settings {
        Settings {
            buttons: buttons.into(),
            close: "close".into(),
            maximize: "full_screen".into(),
            minimize: "app_menu".into(),
        }
    }

    fn ids(t: &Value) -> Vec<(String, String)> {
        t["buttons"]
            .as_array()
            .unwrap()
            .iter()
            .map(|b| {
                (
                    b["id"].as_str().unwrap().into(),
                    b["action"].as_str().unwrap().into(),
                )
            })
            .collect()
    }

    #[test]
    fn no_title_without_a_card_a_style_title_bar_or_with_the_switch_off() {
        let open = json!({"panel": "quick", "face": ""});
        assert!(title_of(&settings("full"), true, &json!({"panel": ""}), None).is_none());
        assert!(title_of(&settings("full"), false, &open, None).is_none());
        assert!(title_of(&settings("off"), true, &open, None).is_none());
        let polkit = json!({"panel": "quick", "face": "", "polkit": true});
        assert!(title_of(&settings("full"), true, &polkit, None).is_none());
    }

    #[test]
    fn close_only_draws_one_button_and_full_draws_three() {
        let open = json!({"panel": "quick", "face": ""});
        let t = title_of(&settings("close"), true, &open, None).unwrap();
        assert_eq!(ids(&t), vec![("close".into(), "close".into())]);
        let t = title_of(&settings("full"), true, &open, None).unwrap();
        assert_eq!(
            ids(&t),
            vec![
                ("minimize".into(), "hide".into()),
                ("maximize".into(), "full_screen".into()),
                ("close".into(), "close".into())
            ]
        );
        assert_eq!(t["full"], false);
    }

    #[test]
    fn a_peek_or_our_own_overlay_does_not_recompute() {
        assert!(only_peek_or_title(&json!({"peek": null})));
        assert!(only_peek_or_title(&json!({"title": {"full": true}})));
        assert!(!only_peek_or_title(
            &json!({"peek": null, "panel": "quick"})
        ));
        assert!(!only_peek_or_title(&json!({"full": "quick:"})));
    }

    #[test]
    fn a_button_set_to_none_is_not_drawn() {
        let mut s = settings("full");
        s.maximize = "none".into();
        let t = title_of(&s, true, &json!({"panel": "quick", "face": ""}), None).unwrap();
        assert_eq!(ids(&t).len(), 2);
        assert!(!ids(&t).iter().any(|(b, _)| b == "maximize"));
    }

    #[test]
    fn the_media_card_finds_its_players_tray_menu() {
        let ui = json!({"panel": "island", "face": "media"});
        let media = json!({"player": "org.mpris.MediaPlayer2.spotify"});
        let tray = json!({"items": [
            {"id": "nm-applet", "title": "Network", "has_menu": true},
            {"id": "spotify-client", "title": "Spotify", "has_menu": true}
        ]});
        assert_eq!(
            app_menu(&ui, &media, &tray).as_deref(),
            Some("spotify-client")
        );
        let no_menu = json!({"items": [{"id": "spotify", "title": "Spotify", "has_menu": false}]});
        assert_eq!(app_menu(&ui, &media, &no_menu), None);
        assert_eq!(
            app_menu(&json!({"panel": "quick", "face": ""}), &media, &tray),
            None
        );
        let t = title_of(&settings("full"), true, &ui, Some("spotify-client")).unwrap();
        assert_eq!(
            t["buttons"][0],
            json!({"id": "minimize", "action": "app_menu", "menu": "spotify-client"})
        );
    }

    #[test]
    fn each_button_does_what_it_says() {
        let s = settings("full");
        // Maximize: full screen for this card, again: back.
        let mut ui = json!({"panel": "island", "face": "clock", "popup": true, "tray": "", "launcher": false});
        press(&s, &mut ui, "maximize", None).unwrap();
        assert_eq!(ui["full"], "island:clock");
        assert_eq!(title_of(&s, true, &ui, None).unwrap()["full"], true);
        // Another card is not full screen.
        let other = json!({"panel": "quick", "face": "", "full": "island:clock"});
        assert_eq!(title_of(&s, true, &other, None).unwrap()["full"], false);
        press(&s, &mut ui, "maximize", None).unwrap();
        assert!(ui.get("full").is_none());
        // Minimize with an app menu: the tray menu of that app.
        let mut media = json!({"panel": "island", "face": "media", "popup": true, "tray": "", "launcher": false});
        press(&s, &mut media, "minimize", Some("spotify")).unwrap();
        assert_eq!(
            (media["panel"].as_str(), media["tray"].as_str()),
            (Some("tray"), Some("spotify"))
        );
        // Minimize without one hides; close closes.
        let mut quick = json!({"panel": "quick", "face": "", "popup": true, "full": "quick:"});
        press(&s, &mut quick, "minimize", None).unwrap();
        assert_eq!(quick["panel"], "");
        assert!(quick.get("full").is_none());
        let mut quick = json!({"panel": "quick", "face": "", "popup": true});
        press(&s, &mut quick, "close", None).unwrap();
        assert_eq!(quick["panel"], "");
        // A button the card does not draw is refused, and nothing changes.
        let mut closed = json!({"panel": "", "face": ""});
        assert_eq!(press(&s, &mut closed, "close", None), Err(NO_BUTTON));
        let mut quick = json!({"panel": "quick", "face": ""});
        assert_eq!(
            press(&settings("close"), &mut quick, "maximize", None),
            Err(NO_BUTTON)
        );
        assert_eq!(quick["panel"], "quick");
    }
}
