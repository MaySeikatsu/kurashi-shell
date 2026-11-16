//! The hash of a mod's tree as Nix computes it (K155, W98; docs/ux/mod-catalogue.md "The index"): SHA-256 over the
//! tree's NAR serialization, written as an SRI string (`sha256-<base64>`). One hash for both routes: the index's
//! `hash` is what `nix hash path` prints for the unpacked source and what `programs.kurashi.mods.<id>.hash` takes, and
//! the daemon checks a download against the same value before it writes anything.
//!
//! NAR (Nix ARchive): strings are a little-endian u64 length, the bytes, zero padding to 8; a node is
//! `( type regular [executable ""] contents <bytes> )`, `( type symlink target <path> )` or
//! `( type directory {entry ( name <n> node <node> )} )` with the entries in byte order of their names.

use std::fs;
use std::io::{self, Read};
use std::path::Path;

use base64::Engine;
use sha2::{Digest, Sha256};

fn put(h: &mut Sha256, bytes: &[u8]) {
    h.update((bytes.len() as u64).to_le_bytes());
    h.update(bytes);
    let pad = (8 - bytes.len() % 8) % 8;
    h.update(&[0u8; 8][..pad]);
}

fn node(h: &mut Sha256, path: &Path) -> io::Result<()> {
    let meta = fs::symlink_metadata(path)?;
    put(h, b"(");
    put(h, b"type");
    if meta.file_type().is_symlink() {
        put(h, b"symlink");
        put(h, b"target");
        put(h, fs::read_link(path)?.as_os_str().as_encoded_bytes());
    } else if meta.is_dir() {
        put(h, b"directory");
        let mut names: Vec<std::ffi::OsString> = fs::read_dir(path)?
            .map(|e| e.map(|e| e.file_name()))
            .collect::<io::Result<_>>()?;
        names.sort_by(|a, b| a.as_encoded_bytes().cmp(b.as_encoded_bytes()));
        for name in names {
            put(h, b"entry");
            put(h, b"(");
            put(h, b"name");
            put(h, name.as_encoded_bytes());
            put(h, b"node");
            node(h, &path.join(&name))?;
            put(h, b")");
        }
    } else {
        put(h, b"regular");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            if meta.permissions().mode() & 0o100 != 0 {
                put(h, b"executable");
                put(h, b"");
            }
        }
        put(h, b"contents");
        // The contents are one NAR string: its length, the bytes (streamed), the padding.
        let len = meta.len();
        h.update(len.to_le_bytes());
        let mut file = fs::File::open(path)?;
        let mut buf = [0u8; 64 * 1024];
        let mut read = 0u64;
        loop {
            let n = file.read(&mut buf)?;
            if n == 0 {
                break;
            }
            h.update(&buf[..n]);
            read += n as u64;
        }
        if read != len {
            return Err(io::Error::other("the file changed while it was read"));
        }
        let pad = (8 - len % 8) % 8;
        h.update(&[0u8; 8][..pad as usize]);
    }
    put(h, b")");
    Ok(())
}

/// The SRI hash of the tree at `path` (a folder, or a single file): `sha256-…`, as `nix hash path` prints it.
pub fn hash(path: &Path) -> io::Result<String> {
    let mut h = Sha256::new();
    put(&mut h, b"nix-archive-1");
    node(&mut h, path)?;
    Ok(format!(
        "sha256-{}",
        base64::engine::general_purpose::STANDARD.encode(h.finalize())
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The values are `nix hash path` (Nix 2.x) over the same trees.
    #[test]
    fn a_tree_hashes_as_nix_hashes_it() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("tea");
        fs::create_dir_all(dir.join("qml")).unwrap();
        fs::write(dir.join("mod.toml"), "id = \"tea\"\n").unwrap();
        fs::write(dir.join("qml/Widget.qml"), "import QtQuick\nItem {}\n").unwrap();
        fs::create_dir_all(dir.join("bin")).unwrap();
        fs::write(dir.join("bin/tea-host"), "#!/bin/sh\necho tea\n").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(dir.join("bin/tea-host"), fs::Permissions::from_mode(0o755))
                .unwrap();
            fs::set_permissions(dir.join("mod.toml"), fs::Permissions::from_mode(0o644)).unwrap();
            fs::set_permissions(
                dir.join("qml/Widget.qml"),
                fs::Permissions::from_mode(0o644),
            )
            .unwrap();
            std::os::unix::fs::symlink("mod.toml", dir.join("link")).unwrap();
        }
        assert_eq!(
            hash(&dir).unwrap(),
            "sha256-WJcwdHFmdA3LZyQ7EC1b2pQZ3N3SParvyjlVk4IET58="
        );
        // One changed byte is another hash; the executable bit is part of it.
        fs::write(dir.join("mod.toml"), "id = \"tee\"\n").unwrap();
        assert_ne!(
            hash(&dir).unwrap(),
            "sha256-WJcwdHFmdA3LZyQ7EC1b2pQZ3N3SParvyjlVk4IET58="
        );
        assert!(hash(&dir.join("missing")).is_err());
    }
}
