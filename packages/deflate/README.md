# deflate

A compressor's container and checksum in Emojicode: bytes in, a gzip stream out. It knows
nothing of HTTP, imports nothing but the standard library, and has no native code.

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
- **Every byte as itself, for now.** A byte costs eight or nine bits, so a stream is as
  long as what went in, or up to an eighth longer, and 20 bytes. Nothing is made smaller
  yet: repeats are not looked for.
- **The checksum and the length** of what went in, at the end.

## Building and testing

`packages/deflate/build.sh [folder]` writes `libdeflate.a` and the interface file `🏛`.
The repository's `./build.sh` builds it with the other packages.

`./build.sh test` runs two things:

- `deflate-tests`: the checksum against known values, the bytes a stream is made of, and
  how large streams get.
- `tests/roundtrip.sh`: every fixture is compressed by `deflate-tool` and given to the
  system's `gzip`, which has to accept the stream and give the fixture back, byte for
  byte. A stream that only our own code could read would pass every other test, so no
  test here reads one with our own code. It needs `gzip` and `perl`, which the image has.
