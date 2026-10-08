# deflate

A compressor in Emojicode: bytes in, a gzip stream out. It knows nothing of HTTP, imports
nothing but the standard library, and has no native code.

```
📦 deflate 🏠

🤐🐇🎈 data❗️ ➡️ stream        💭 what `gzip -dc` turns back into data
🧾🐇🎈 data❗️ ➡️ checksum      💭 the CRC-32 that such a stream ends with
```

| Call | Meaning |
|---|---|
| `🤐🐇🎈 data❗️` | *data*, a `📇`, as a gzip stream (RFC 1952), also a `📇`. |
| `🧾🐇🎈 data❗️` | The CRC-32 of *data*, the checksum that gzip, zip and PNG use, as a number from 0 to 4294967295. |

There is no way to read a stream back. Whatever reads gzip does: `gzip -dc`, a browser,
any HTTP client.

## What a stream is made of

- **The ten bytes every gzip stream begins with**, with no file name and no time in them.
  The same input gives the same stream, byte for byte, every time and on every machine.
- **One deflate block with the fixed codes** (RFC 1951, 3.2.6). The codes are the ones
  the format gives for nothing: none are worked out from the input and none are sent.
- **Repeats.** Three bytes or more that came before, within the last 32,768, are written
  as "so many bytes from so far back". Places are found again through a table of their
  first three bytes. A search looks at the eight nearest places that share a slot of
  that table, takes the longest repeat among them, and goes on behind it.
- **The checksum and the length** of what went in, at the end.

## What it gives, and what it costs

Measured in the repository's image on an Apple M5 Pro, where the image's x86-64 code runs
under emulation. A machine that runs it as it is will be faster; the proportions hold.

| Input | Bytes | Stream | Time | `gzip -1` | `gzip -6` |
|---|---|---|---|---|---|
| A JSON list of 400 records | 26,214 | 3,360 | 13 ms | 2,955 | 2,598 |
| This repository's README | 25,839 | 13,602 | 16 ms | 12,084 | 10,930 |
| A megabyte of this repository's sources | 1,048,576 | 300,218 | 367 ms | 293,485 in 10 ms | 233,243 in 26 ms |
| 300,000 bytes without pattern | 300,000 | 316,299 | 104 ms | | |
| A megabyte of one byte | 1,048,576 | 6,627 | 277 ms | | |
| A megabyte made to keep the search busy | 1,048,576 | 1,009,119 | 633 ms | | |

- **Text becomes a half to a quarter of its size, and JSON an eighth.** `gzip -1` gets
  2 to 14 percent less than that, and `gzip -6` a fifth to a quarter less: it works out
  codes for each input (dynamic Huffman codes), where this uses the fixed ones, and it
  looks at more places for a repeat. Both are left for later.
- **Bytes without pattern grow, by an eighth at most, and 20 bytes.** A byte that
  repeats nothing costs eight or nine bits. A caller that minds compares the two lengths
  and keeps the shorter.
- **It is slow beside the C library**: about 0.4 milliseconds for each kilobyte here,
  which is thirty-five times what `gzip -1` takes on the same machine. Where a proxy in
  front can compress, let it.
- **The work is bounded.** However the input is made, a search looks at eight places and
  no more, and stops at the longest repeat there can be, 258 bytes. Input that was
  written to keep a compressor busy costs less than twice what text costs.
- **Memory:** two tables of up to 32,768 numbers each for the length of one call, sized
  down for input shorter than that, and the stream itself.

## Building and testing

`packages/deflate/build.sh [folder]` writes `libdeflate.a` and the interface file `🏛`.
The repository's `./build.sh` builds it with the other packages.

`./build.sh test` runs two things:

- `deflate-tests`: the checksum against known values, the bytes a stream is made of, and
  how large streams get.
- `tests/roundtrip.sh`: every fixture is compressed by `deflate-tool` and given to the
  system's `gzip`, which has to accept the stream and give the fixture back, byte for
  byte. A stream that only our own code could read would pass every other test, so no
  test here reads one with our own code. The fixtures are the ones that the format's
  edges ask for: nothing, one byte, every byte value, a run of 258 bytes and of one more,
  a repeat as far back as one may reach and one byte further, a repeat that reaches into
  itself, input too short to hold a repeat, and a megabyte each of text, of one byte and
  of bytes chosen to fall into one slot of the table. It also holds a fixed text to the
  size its stream has had, so that a search that begins to find fewer repeats is
  noticed, and holds the megabytes of one byte and of chosen bytes to twice the time
  that text takes. It needs `gzip`, `perl` and `shuf`, which the image has.
