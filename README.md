# hop

Fast & simple archive format designed for quickly reading individual files or a handful of individual files. Possibly will be used in [Bun](https://bun.sh).

25x faster than `zip` and 15x faster than `tar` at reading individual files

<img src="https://user-images.githubusercontent.com/709451/141064938-1384381d-6c2f-4ecb-a1c3-a9c15333b6b9.png" />

| Format | Fast random access | Fast at extracting | Fast at archiving | Compression | Encryption | Mature |
| ------ | ------------------ | ------------------ | ----------------- | ----------- | ---------- | ------ |
| hop    | ✅                 | ✅                 | ✅                | ❌          | ❌         | ❌     |
| tar    | ❌                 | ✅                 | ✅                | ❌          | ❌         | ✅     |
| zip    | ✅ (when small)    | ❌                 | ❌                | ✅          | ✅         | ✅     |

Features:

- Faster at printing individual files than `tar` & `zip` (with compression disabled on both)
- Faster extraction than `zip`and +/- 10% faster than `tar` (with compression disabled on both)
- Faster archiving than `zip` and +/- 10% faster than `tar` (with compression disabled on both)

Anti-features:

- Single-threaded (but doesn't need to be)
- I wrote it in about 3 hours and there are no tests
- No checksums yet. Probably not a good idea to use this for untrusted data until that's fixed.
- Ignores symlinks
- Can't be larger than 4 GB
- Archives are read-only and file names are not normalized across platforms

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

## Some benchmarks

#### On macOS 12 with an M1X

Using [tigerbeetle](https://github.com/coilhq/tigerbeetle) github repo as an example

Archiving:

![image](https://user-images.githubusercontent.com/709451/141054452-73a99912-94ce-44aa-b7cb-b788731d0a60.png)

Extracting:

![image](https://user-images.githubusercontent.com/709451/141054517-cb3c7b43-4730-40ee-9c3f-7bdd9de6a076.png)

#### On an Ubuntu AMD64 server

Extracting a `node_modules` folder

![image](https://user-images.githubusercontent.com/709451/141056480-0cd4ea66-efb7-41cf-a406-06e10ac8c889.png)

## Why faster?

- It stores an array of hashes for each file path and the file paths are sorted lexigraphically
- Does not store directories, only files
- Does not support appending to the existing file
- [`copy_file_range`](https://man7.org/linux/man-pages/man2/copy_file_range.2.html)
- `packed struct` makes serialization & deserialization very fast because there is very little encoding/decoding step.

### How does it work?

1. File contents go at the top, file metadata goes at the bottom
2. This is the metadata it currently stores:

```
package Hop;

struct StringPointer {
    uint32 off;
    uint32 len;
}

struct File {
    StringPointer name;
    uint32 name_hash;
    uint32 chmod;
    uint32 mtime;
    uint32 ctime;
    StringPointer data;
}

message Archive {
    uint32 version = 1;
    uint32 content_offset = 2;
    File[] files = 3;
    uint32[] name_hashes = 4;
    byte[] metadata = 5;
}
```
