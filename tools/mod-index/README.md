# The mod index (K155, W98)

The catalogue is an **index repository**: one file per mod, `mods/<id>.toml`, and an `index.json` built from them that
the shell fetches when Browse is opened (docs/ux/mod-catalogue.md). `example/` is such a repository with one entry.

- An entry names each version's source (a git URL with a full revision, or an archive, over https), the shell versions
  it fits, and the **hash of the unpacked tree** — `kurashi mod hash <folder>`, the same value `nix hash path <folder>`
  prints, so one hash serves the in-app install and `programs.kurashi.mods.<id>`.
- `[version.summary]` (what the mod adds, reads, may reach and runs) is written by CI from the mod's own manifest:
  `build.py summary <index> <id>`. Nobody types it.
- A pull request is the review. CI: `build.py check <index> --fetch` (each source fetched, its hash compared,
  `kurashi mod check` run on it); after the merge `build.py build <index>` writes `index.json`.

`test.py` runs the script against a mod scaffolded on the spot (no network): a matching hash passes, a changed tree is
refused, the summary and `index.json` come out as the shell reads them.
