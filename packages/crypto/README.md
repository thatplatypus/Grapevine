# crypto

Hashing and signing in Emojicode: bytes in, bytes or text out. The package knows nothing
of HTTP or of tokens, imports nothing but the standard library, and has no native code.

To [Packmoji](https://github.com/thatplatypus/Packmoji), the package manager for Emojicode,
this is `@thatplatypus/crypto`. The [`packmoji.json`](packmoji.json) beside this file says
so, and gives its version. To add it to a project:

```
pmj add @thatplatypus/crypto --repository github.com/thatplatypus/grapevine
```

The last part says where the package lives, since it shares its repository with others. A
project that already depends on `@thatplatypus/grapevine` can leave it out: `pmj` then finds
this package beside that one.

```
📦 crypto 🏠

🔨🐇🖋 data❗️ ➡️ digest            💭 SHA-256: 32 bytes
✍️🐇🖋 key data❗️ ➡️ signature      💭 HMAC-SHA-256: 32 bytes
👯🐇🖋 one other❗️ ➡️ same          💭 the same bytes, compared in constant time
🧵🐇🖋 data❗️ ➡️ text              💭 base64url, without padding
🧶🐇🖋 text❗️ ➡️ data              💭 and back, or no value
🎹🐇🖋 data❗️ ➡️ text              💭 lower-case hex
```

| Call | Meaning | Checked against |
|---|---|---|
| `🔨🐇🖋 data❗️` | The SHA-256 of *data*, a `📇` (FIPS 180-4): 32 bytes, as a `📇`. | The examples of FIPS 180-4 and of NIST, a million `a` among them, and the system's `sha256sum` for every length from 0 to 130 bytes and for larger inputs. |
| `✍️🐇🖋 key data❗️` | The HMAC-SHA-256 of *data* under *key* (RFC 2104): 32 bytes that only someone who has the key can make, and anyone who has it can check. A key of any length. | The seven test cases of RFC 4231, and `openssl` for keys of 1 to 200 bytes, those around the 64 of a block among them. |
| `👯🐇🖋 one other❗️` | Whether two byte strings are the same. Every byte of both is looked at, so the time it takes says how long they are and not where they differ. | Its answers. See below for the time. |
| `🧵🐇🖋 data❗️` | *data* as base64url (RFC 4648, section 5) without padding: the alphabet that can stand in an address. | RFC 4648's examples, and `perl`'s `MIME::Base64` for a hundred inputs of the test's own making. |
| `🧶🐇🖋 text❗️` | The bytes that *text* stands for, or no value when it is not base64url as `🧵` writes it. | Every length of input from 0 to 64 read back, and each kind of text that is refused. |
| `🎹🐇🖋 data❗️` | *data* as hex digits in lower case, two for each byte. | Every other check, which compares digests as hex. |

## What it is for, and what it is not for

- **For** telling whether bytes are the bytes they were (a digest), for signing a message
  with a key that both sides have (an HMAC), and for checking such a signature. A JSON Web
  Token signed with HS256 is exactly that, and
  [grapevine](https://github.com/thatplatypus/Grapevine/blob/main/packages/grapevine/README.md)
  builds its tokens on this package.
- **Compare signatures with `👯`, never with `🙌`.** A comparison that stops at the first
  byte that differs tells whoever is guessing how many bytes they have right.
- **Not for passwords.** A digest is fast, and that is the wrong thing for a password:
  whoever steals the digests tries many millions of guesses a second. A password wants a
  function that is slow on purpose (PBKDF2, bcrypt, scrypt, Argon2), and none is here. A
  hundred thousand rounds of HMAC in Emojicode would take several seconds of a worker's
  time for each sign-in.
- **No key pairs.** No RSA, no elliptic curves: nothing that one side can check and not
  make.
- **No random numbers.** A key has to come from the system, and this package has no
  native code to ask it. grapevine's socket shim does (`🎲🐇🔩`).
- **No decoder that forgives.** `🧶` refuses padding, the characters `+` and `/` of the
  other alphabet, white space, a length that no number of bytes gives, and left-over bits
  that are not zero. Each of those would give one signature a second spelling.

## Constant time, and what that can mean here

`👯` has no branch that depends on the bytes it compares: it gathers every difference into
one number and looks at that number once, at the end. That is the property that can be
read off its source, and it is all that is claimed. The compiler is not ours, the code is
not optimised, and nothing here was measured with a stopwatch: a claim about nanoseconds
would be a guess. Two strings of different lengths are told apart at once, which gives
away a length. A digest's length is no secret.

## What it costs

Measured in the repository's image on an Apple M5 Pro, where the image's x86-64 code runs
under emulation. A machine that runs it as it is will be faster.

| Work | Time |
|---|---|
| SHA-256 of a megabyte | about 160 ms: 6 MB a second |
| HMAC-SHA-256 of a message of 200 bytes, with a key of 32 | about 0.1 ms |

`sha256sum` hashes 220 MB a second on the same machine, thirty-five times as much. For
signatures over short messages, which is what a token is, a tenth of a millisecond is
not what a request waits for.

## Building and testing

`packages/crypto/build.sh [folder]` writes `libcrypto.a` and the interface file `🏛`. The
repository's `./build.sh` builds it with the other packages.

`./build.sh test` runs two things:

- `crypto-tests`: the published examples for each call, the comparison's answers, and
  each kind of text that `🧶` refuses.
- `tests/against.sh`: digests, signatures and encodings of inputs of the test's own
  making, each compared with what a tool of the system gives for the same input:
  `sha256sum`, `openssl` and `perl`. A digest that is right for the examples of the
  standard and wrong for other lengths would pass every other test, so no test here
  asks our own code whether our own code is right. It also holds a megabyte and a
  thousand signatures to ten seconds each, to notice a hash that has become ten times
  slower.
