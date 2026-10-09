//! power-profiles-daemon (`net.hadess.PowerProfiles`): the active profile and the profiles it offers,
//! as `svc.power` shows them. The daemon not being on the bus, or not answering, is "unknown"
//! (`profile_reason`), never a guessed profile (rule 2).

use std::collections::HashMap;

use zbus::Connection;
use zbus::zvariant::OwnedValue;

use crate::util;

pub const DEST: &str = "net.hadess.PowerProfiles";
pub const PATH: &str = "/net/hadess/PowerProfiles";
const IFACE: &str = "net.hadess.PowerProfiles";

/// i18n key: the daemon is not on the bus, or does not answer.
pub const UNAVAILABLE: &str = "error.power.profiles_unavailable";

/// What the daemon reports when it answers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Profiles {
    pub active: String,
    /// In the daemon's order (power-saver, balanced, performance).
    pub names: Vec<String>,
}

/// Why a profile change did not happen.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProfileError {
    /// Not one of the profiles the daemon offers.
    Unknown,
    /// The daemon's authorisation (polkit) said no.
    Refused,
    /// The daemon is not on the bus, or the write failed for another reason.
    Unavailable,
}

/// The daemon's state, or the i18n key that says why there is none.
pub async fn read(conn: &Connection) -> Result<Profiles, &'static str> {
    if !util::name_has_owner(conn, DEST).await {
        return Err(UNAVAILABLE);
    }
    let props = util::get_all(conn, DEST, PATH, IFACE)
        .await
        .ok_or(UNAVAILABLE)?;
    let active = util::prop::<String>(&props, "ActiveProfile").ok_or(UNAVAILABLE)?;
    let offered =
        util::prop::<Vec<HashMap<String, OwnedValue>>>(&props, "Profiles").ok_or(UNAVAILABLE)?;
    let names: Vec<String> = offered
        .iter()
        .filter_map(|p| p.get("Profile"))
        .filter_map(|v| v.try_clone().ok())
        .filter_map(|v| String::try_from(v).ok())
        .collect();
    if names.is_empty() {
        return Err(UNAVAILABLE);
    }
    Ok(Profiles { active, names })
}

/// Switches the daemon's active profile. A name the daemon does not offer is refused before the
/// write, so nothing is sent for it. The reply comes back through the document (rule 2).
pub async fn set(conn: &Connection, name: &str) -> Result<(), ProfileError> {
    let current = read(conn).await.map_err(|_| ProfileError::Unavailable)?;
    if !current.names.iter().any(|n| n == name) {
        return Err(ProfileError::Unknown);
    }
    let proxy = zbus::fdo::PropertiesProxy::builder(conn)
        .destination(DEST)
        .and_then(|b| b.path(PATH))
        .map_err(|_| ProfileError::Unavailable)?
        .build()
        .await
        .map_err(|e| classify(&e))?;
    proxy
        .set(
            IFACE.try_into().map_err(|_| ProfileError::Unavailable)?,
            "ActiveProfile",
            zbus::zvariant::Value::from(name),
        )
        .await
        .map_err(|e| {
            let e = zbus::Error::from(e);
            tracing::warn!(error = %e, "power-profiles-daemon did not switch the profile");
            classify(&e)
        })
}

fn classify(e: &zbus::Error) -> ProfileError {
    match e {
        zbus::Error::MethodError(name, _, _)
            if name.as_str() == "org.freedesktop.PolicyKit1.Error.NotAuthorized"
                || name.as_str() == "org.freedesktop.DBus.Error.AccessDenied" =>
        {
            ProfileError::Refused
        }
        zbus::Error::FDO(e) if matches!(**e, zbus::fdo::Error::AccessDenied(_)) => {
            ProfileError::Refused
        }
        _ => ProfileError::Unavailable,
    }
}
