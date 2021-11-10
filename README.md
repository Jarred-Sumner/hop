# hop

Fast, simple, and highly experimental archive format. Possibly will be used in [Bun](https://bun.sh).

Features:

- Faster extraction than `tar` & `zip` (with compression disabled on both)
- Faster archiving than `tar` & `zip` (with compression disabled on both)
- Faster at printing individual files than `tar` & `zip` (with compression disabled on both)

Anti-features:

- Single-threaded (but doesn't need to be)
- I wrote it in about 3 hours
- Like tar, does not answer compression
- No checksums yet. Probably not a good idea to use this for untrusted data until that's fixed.

## Usage

Download the binary from /releases

To create an archive:

```bash
hop ./path-to-folder
```

To extract an archive:

```bash
hop archive.hop
```

To print one file from the archive:

```bash
hop archive.hop package.json
```

## Why faster?

- [`copy_file_range`](https://man7.org/linux/man-pages/man2/copy_file_range.2.html)
- `packed struct` makes serialization & deserialization very fast because there is very little encoding/decoding step.
