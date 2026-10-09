use std::fmt;

use zeroize::Zeroizing;

/// A secret that is wiped on drop and never printed. Deliberately no `Clone`, `Serialize`
/// or `Display`: the only way out is `expose`.
pub struct SecretString(Zeroizing<String>);

impl SecretString {
    pub fn new(s: impl Into<String>) -> Self {
        Self(Zeroizing::new(s.into()))
    }
    pub fn expose(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for SecretString {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("SecretString([REDACTED])")
    }
}
