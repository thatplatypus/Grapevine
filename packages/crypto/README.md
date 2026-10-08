# crypto

Hashing in Emojicode: bytes in, a digest out. The package knows nothing of HTTP or of
tokens, imports nothing but the standard library, and has no native code.

```
📦 crypto 🏠

🔨🐇🖋 data❗️ ➡️ digest        💭 SHA-256: 32 bytes
🎹🐇🖋 data❗️ ➡️ text          💭 lower-case hex
```

| Call | Meaning |
|---|---|
| `🔨🐇🖋 data❗️` | The SHA-256 of *data*, a `📇` (FIPS 180-4): 32 bytes, as a `📇`. |
| `🎹🐇🖋 data❗️` | *data* as hex digits in lower case, two for each byte. |

## Building and testing

`packages/crypto/build.sh [folder]` writes `libcrypto.a` and the interface file `🏛`. The
repository's `./build.sh` builds it with the other packages.

`./build.sh test` runs two things:

- `crypto-tests`: digests against the examples of FIPS 180-4 and of NIST.
- `tests/against.sh`: digests of inputs of every length from 0 to 130 bytes, and of
  larger ones, against the system's `sha256sum`. A digest that is right for the
  standard's examples and wrong for other lengths would pass every other test.
