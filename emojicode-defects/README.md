# Defects found in Emojicode 1.0 beta 2

These were found while building an HTTP server framework in Emojicode: some fifteen
thousand lines of it, and nearly as many of tests. Each defect has a short program here
that shows it. The programs import nothing but the standard library, except for
`43`, which is about the stock `json` package, and `07` and `44`, which are about
packages and bring two small ones of their own.

- **The release**: `Emojicode-1.0-beta.2-Linux-x86_64` from the releases page, on Ubuntu
  22.04 (glibc 2.35, GNU ld 2.38), on x86-64 under emulation on an Apple Silicon Mac.
  What the programs do was seen there and nowhere else. The statuses, the allocator's
  messages and the linker's behaviour are that system's, and we had no other to try.
- **How it was set up**, in a container of `ubuntu:22.04`:

  ```sh
  apt-get update && apt-get install -y --no-install-recommends build-essential curl ca-certificates libtinfo5
  curl -fsSL https://github.com/emojicode/emojicode/releases/download/v1.0-beta.2/Emojicode-1.0-beta.2-Linux-x86_64.tar.gz | tar -xz -C /opt
  cd /opt/Emojicode-1.0-beta.2-Linux-x86_64
  cp emojicodec /usr/local/bin/
  mkdir -p /usr/local/EmojicodePackages /usr/local/include/emojicode
  cp -r packages/* /usr/local/EmojicodePackages/ && cp -r include/* /usr/local/include/emojicode/
  ```

- **The source that is cited**: the repository at `v1.0-beta.2-21-g4dec45b4`, which is
  21 commits after the release. Two of them bear on this page: `2016d097` fixes #189,
  which is `01` here, and `268f85c1` fixes #187, which is the assertion of `05` reached
  another way. Everything else that is cited reads there as it does in the release.
- **To run them all**: `./run.sh`, on Linux (it reads `/proc` and uses `timeout`), where
  `emojicodec` is on the path. It builds and runs every program and compares what each
  did with what this page says: a compiler that fails, a program that crashes, a line
  of output, or memory that grows. It prints a line for each and ends with 0 when every
  defect is still there.
- **One program by hand**: `emojicodec 15-bound-cast-releases-twice.🍇 && ./15-bound-cast-releases-twice`.
  The two that need a package have a folder and a `build.sh`.

Each program begins with a comment that says what to expect and what happens instead.
"Instead" at the end of an entry is the spelling we use to stay clear of the defect,
which also shows how narrow each one is. A number is a program's name and no more: the
tables below are in the order of the page, and some numbers are not used.

## How a leak is measured

A program in the third and fourth groups runs a loop a number of times that it names
in a line of its own (`200000 ➡️ rounds`). `run.sh` builds it as it is and with four
times the rounds, runs both, and reads each one's high-water mark of resident memory
from `/proc` (`VmHWM`). `20-steady.🍇` is the measurement's own check: a loop that makes a
text in every round and lets it go holds between 6,808 and 6,980 kB, at 200,000 rounds
as at 800,000.

## The compiler

| Program | What it shows |
|---|---|
| `09-reraise-of-a-subclass.🍇` | **The compiler ends with status 0 when LLVM's verifier refuses the code it generated.** It prints what the verifier said and `Detected in:` with the function's name (`Compiler/Generation/FunctionCodeGenerator.cpp`), and goes on to write the program. A build script cannot tell that anything went wrong without reading the output. Here the code that is refused is a `🔺` around a call that raises a subclass of the error its own function raises: `Call parameter type does not match function signature!`. `ASTReraise::generate` hands the function's error pointer to the call as it is, and the call was declared with a pointer to the subclass. This program happens to run. The next one does not. |
| `01-interpolated-element.🍇` | `🔤first: 🧲🐽 list 0❗️🧲🔤` is refused by the verifier in the same way, `Stored value type does not match pointer operand type!`, the compiler ends with 0, and the program is a segmentation fault at that line. The miscompile is **#189, fixed on master by `2016d097` and in no release**: it is here because the release is what people install. Instead: hold the element in a variable first. |
| `02-and-frees-earlier-temporaries.🍇` | **A `🤝` or a `👐` frees whatever its statement made before it.** `ASTBinaryOperator::generateLogical` calls `releaseTemporaryObjects()` after each of its two sides, and that releases every temporary the statement has made so far, not only those of the two sides. An object made earlier in the statement, as an earlier argument or as the receiver, is freed before the call that was to get it: `👌 t 🆕🔡 🍿 … 🍆 🔤🔤❗️ a 🙌 3 🤝 b 🙌 5❗️` hands `👌` a text that has been freed. In the program the text reads otherwise by then. With an interpolated text in its place, or a fresh object that holds a text as the receiver, it is a segmentation fault. Instead: put the test into a variable first. A `🤝` that comes before the object is made is fine too. |
| `03-nan-compares-equal.🍇` | Comparisons of reals are compiled as LLVM's unordered ones (`FCmpUEQ`, `FCmpULT` and the rest, `Compiler/AST/ASTBinaryOperator_CG.cpp`), each of which is true when either side is a NaN. So a NaN is equal to 0.0, below it and above it, and equal to itself plus one. A loop that waits for a comparison to turn false never ends on one. |
| `05-fresh-object-of-later-class.🍇` | A fresh object of a class that is declared further down the file, handed straight to a method that only borrows it, aborts the compiler: `MFFlowCategory.hpp:31: … Assertion '!isUnknown()' failed`. `ASTInitialization::analyseMemoryFlow` asks whether the initializer keeps its object before it calls `analyseFunctionCall`, so before the initializer has been analysed. #187 was the same assertion reached through `⤴️🆕`, and `268f85c1` fixed it in `ASTSuper::analyseMemoryFlow` by asking afterwards: the same change of order looks right here. A compiler built without assertions would read "unknown" as "does not escape" and put the object on the stack. Instead: bind the object to a variable first. |
| `06-optional-then-cast.🍇` | A value taken out of an optional `⚪️` with `↪️ … ➡️ value` and then cast with `🔲 value 🔡` aborts the compiler: `Type.hpp:346: … Assertion 'genericArguments_.front().type() != TypeType::Box' failed`. We did not trace the cause. Instead: cast the optional itself. |
| `45-any-as-a-parameter.🍇` | A method with a parameter of type `⚪️` aborts the compiler: `Type.cpp:91: … Type::typeDefinition() const: Assertion 'type() == TypeType::Class \|\| type() == TypeType::Protocol \|\| …' failed`. The method need not be called: that it is declared is enough, and a closure with such a parameter does the same. A `⚪️` that is returned, held in a variable, or inside a list that is a parameter (`🍨🐚⚪️🍆`) is fine. We did not trace the cause. |
| `07-closure-in-a-small-function/` | A package has a method of two statements that lets its own object go and hands a closure which is not `🎍🥡` to a method that only calls it. The package compiles. A program that imports it does not: `🏛:12:12: error: Using non-escaping closure as escaping value`. Every function of two statements or fewer is written into the interface file with its body (`Function::isInline`), and this one is marked `🎍🥡` there. A function that is marked already is not analysed by the importing compile (`MFFunctionAnalyser::analyse` returns at once), so the closure in it is never given its place on the stack, and `ASTClosure::generate` then takes it for one that should have been escaping. With `🎍🥡` on the closure both compile, and the package's own compile warns `Using escaping closure as non-escaping value`. |
| `44-package-link-order/` | A program imports a package that imports another. The link fails with `undefined reference` to the inner package's symbols. A package is put on the list of imports before its own imports are loaded (`Compiler::loadPackage`), and the link line walks that list backwards (`Compiler::LinkPhase::perform`), so the inner package's archive comes before the one that needs it, and a linker that reads each static archive once passes it over. The result of `system` is not looked at, so the compiler **ends with status 0** here too, though no program was linked. Instead: import the inner package in the program as well, before the outer one. Or compile with `-c` and link by hand, with the archives between `-Wl,--start-group` and `-Wl,--end-group`. |

## Memory that is freed, or left on a dead frame, while it is in use

All six are segmentation faults.

| Program | What it shows |
|---|---|
| `10-reraise-hides-an-escape.🍇` | A new object held in a local and passed to a call wrapped in `🔺`, which keeps it, is gone when the function returns. The arguments of a call that is wrapped in `🔺` are not analysed (`ASTReraise::analyseMemoryFlow`), so the compiler never learns that the object leaves, and places it in the caller's frame. A `🆗` that binds no value has the same blind spot. It bites only where the callee keeps what it is given. Instead: `🆗 value call❗️ 🍇 … 🍉 🙅‍♀️ error 🍇 … 🍉`, where the call is made. |
| `11-returning-a-parameter.🍇` | `↩️ value`, where `value` is a parameter, returns it without retaining it, and the caller releases what it got as if it had been retained. `ASTGetVariable::analyseMemoryFlow` marks the variable as returned, which makes `generate` leave the retain out, and `MFFunctionAnalyser::recordVariableGet` returns early for a parameter, so nothing makes up for it. With a temporary as the argument the text is freed while the caller holds it, and the next text that is made takes its place. Instead: `value ➡️ kept`, then `↩️ kept`. |
| `12-returning-self.🍇` | A setter that chains, ending in `↩️ 👇`, called on a fresh object: `💬 🆕🆘 404❗️ 🔤not here🔤❗️`. `MFFunctionAnalyser::recordThis` does not count a return as an escape, so the method is taken to borrow its object, the fresh object is placed in the caller's frame, and the method's result is that same object, gone when the caller returns it. Instead: `👇 ➡️ same`, then `↩️ same`. |
| `13-declared-after-a-handler.🍇` | A variable declared without a value (`🖍🆕 later 🔡`) further down a function that has handled an error with `🆗 … 🙅‍♀️` is assigned as if it already held an object. The handler's value and its error share a slot, slots are handed out again when a scope ends, and `finishMutualExclusiveBranches` (`Compiler/Analysis/PathAnalyser.cpp`) makes the slot "initialised" for good. The first assignment releases whatever the stack holds there. Instead: declare the variable before the `🆗`, or with a value. |
| `14-failed-cast-frees.🍇` | A downcast that fails, handed straight to a call (`👀 🔲 thing 🎈❗️`), releases the object once for each failing cast. `ASTCast::downcast` (`Compiler/AST/ASTCast_CG.cpp`) releases the value in its failing branch on the assumption that it was retained, which is so only when the cast is bound. Instead: `↪️ 🔲 thing 🎈 ➡️ balloon 🍇`. |
| `15-bound-cast-releases-twice.🍇` | The mirror of `14`, for a cast that is no downcast of a class. A `⚪️` held in a variable, cast with `🔲 value 🔡`, and the cast **bound** to a variable, is released twice: once for each of the two variables. `ASTCast::analyse` asks for the operand by reference on that path, `ASTGetVariable::generate` returns a variable's address before it reaches the retain, and the variable that the cast is bound to then owns a reference that nobody took. A value of a protocol's type cast to its class does the same. Upstream's `tests/compilation/castAny.emojic` binds only casts that fail. This was the double free that we first took for the stock `json` parser's, whose values are `⚪️`. Instead: use the cast where it stands and do not bind it (`📐 🍺 🔲 value 🔡❗️`), or bind the cast of what a call gives (`↪️ 🔲 🐽 dictionary 🔤key🔤❗️ 🔡 ➡️ text 🍇`). |

## Memory that is never released

Measured as described above. The figures are from one run, and those of other runs
differed from them by less than half a megabyte.

| Program | What it shows | High-water mark after 200,000 rounds, and after 800,000 |
|---|---|---|
| `21-interpolation-leaks.🍇` | An interpolated text leaks the text form of every value it inserts: `ASTInterpolationLiteral::generate` (`Compiler/AST/ASTLiterals_CG.cpp`) appends what the value's `🔡` gave and never releases it. Instead: join a list, `🆕🔡 🍿 a b 🍆 🔤🔤❗️`. | 35,096 kB and 119,472 kB |
| `22-return-in-else.🍇` | A `↩️` directly inside a plain `🙅 🍇` block releases none of the function's locals. `ASTIf::analyseMemoryFlow` (`Compiler/AST/ASTControlFlow.cpp`) never pops the scope of the else block. Instead: no `🙅` there. The `↪️` returns, and the other `↩️` is the function's last statement. | 28,852 kB and 94,480 kB |
| `23-variable-in-else.🍇` | A variable declared directly inside a plain `🙅 🍇` block is never released, for the same reason. Instead: `🙅↪️ 👍 🍇 … 🍉`. | 44,480 kB and 156,980 kB |
| `24-returning-a-local-early.🍇` | `↩️ name` from the middle of a function marks the variable's slot as returned. The mark is never cleared, so every way out after it skips that variable: a later `↩️`, the end of a loop's round, and the error exit of a later `🔺`. Instead: a local is returned by the last statement only. | 44,480 kB and 156,980 kB |
| `25-new-list-over-a-variable.🍇` | `🆕🍨🐚🔡🍆❗️ ➡️ 🖍list` over a list builds the new one in place without releasing the old (`ASTVariableInit::generate`, `Compiler/AST/ASTVariables_CG.cpp`). The same for a dictionary. Instead: empty the list with `🐗`. | 138,224 kB and 531,976 kB |
| `26-return-in-unsafe-block.🍇` | A `↩️` directly inside a `☣️` block releases none of the function's locals either: such a block has no scope of its own to pop. Instead: hand the value out of the block and return it after. | 28,852 kB and 94,480 kB |

## The standard library and the stock packages

Three of the first four are the compiler's defects above, met in the library's own code.

| Program | What it shows |
|---|---|
| `30-data-slice-leaks.🍇` | `🔪` on `📇` leaks on every call: 22,592 kB after 200,000 rounds and 69,468 kB after 800,000, where the steady program holds under 7,000. The method returns from inside a `☣️` block: `26` above, in the library itself. |
| `31-data-join-leaks.🍇` | `➕` on `📇` likewise: 31,976 kB and 106,972 kB. |
| `32-text-split-leaks.🍇` | `🔫` on `🔡` likewise: 106,976 kB and 406,976 kB, for a text split in eight. `🔫` cuts each piece with its helper `🗡` (`s/🔡.🍇`), which returns from inside a `☣️` block. |
| `33-dictionary-leaks.🍇` | A dictionary leaks an entry whenever a key is looked up or set in a bucket that holds another key. The private `🔍` of `🍯` (`s/🍯.🍇`) walks the bucket's chain and returns its loop's variable from inside the loop, which is `24` above in the library itself: an entry that the walk goes past is never released. 100,000 dictionaries of one key, each asked for twenty keys that it does not have, leave 22,616 kB behind, and 400,000 leave 69,492 kB. Which keys share a bucket changes from run to run, since the hash of a text is seeded at random when the process starts: with eight keys set and nothing looked up, the same 100,000 dictionaries left between 23 MB and 163 MB in twenty runs, and a test for leaks passes and fails by turns. |
| `34-lower-case-overflows.🍇` | `📪` and `📫` allocate exactly as many bytes as the text has and write the converted letters without a bound. `Ⱥ` (U+023A) is two bytes and its lower-case form three, so a text of them overruns: `malloc(): corrupted top size`, and the process aborts. |
| `35-bytes-taken-for-text.🍇` | `🔡 data❗️` returns a text for the bytes `FF FE`. Its documentation says that no value is returned for bytes that are not UTF-8. `sDataAsString` (`s/Data.cpp`) has `// TODO: validate` where the check would be. |
| `36-lowest-integer-as-text.🍇` | `🔡 n 10❗️` for -9223372036854775808 gives twenty bytes of which eighteen were never written. `sIntToString` (`s/Integer.cpp`) takes the absolute value with `std::abs`, which stays negative for this one integer, so one "digit" is read from in front of the table of digits and the loop that writes them ends at once. |
| `37-trim-cuts-a-character.🍇` | `🔧` on `🔤Port Hermes to 🍇🔤`, which has nothing to trim, gives back 16 bytes of its 19: the last character is cut in the middle. `sStringTrim` (`s/String.cpp`) takes the end of the text to be the first byte of its last character. |
| `38-digits-above-thirty-one.🍇` | `🔡 32 36❗️` is `x`, and `🔡 35 36❗️` is `0`. The table of digits in `sIntToString` is `"0123456789abcdefghijklmnopqrstuvxyz"`, which has no `w`. |
| `39-thread-let-go.🍇` | A `🧵` whose last reference is dropped before it was joined aborts the process when the thread object is released: `terminate called without an active exception`. |
| `41-last-of-an-empty-list.🍇` | `🐼` on an empty list lowers the count to -1 and reads the memory in front of the list. Its documentation says that no value is returned. A segmentation fault here. |
| `43-json-without-a-depth.🍇` | The stock `json` parser calls itself once for every `[` and has no limit: 200,000 of them run the stack out, and the process ends where a 🚧🔸🌸 was to be raised. |

## Meant, it seems, and easy to step into

These three are how the language is, as far as the source says. They are here because
each cost us time, and because a word in the documentation or in a message would have
saved it.

| Program | What it shows |
|---|---|
| `04-real-with-exponent.🍇` | `2.5e3` does not compile: `Variable "e3" not defined`. A real has no exponent form: `Lexer::continueDoubleToken` goes on for digits only. The message is about a variable that nobody wrote. |
| `08-override-keeps-parameter.🍇` | A method that overrides another and keeps a parameter which the method it overrides only uses is refused: `Function lets parameter "line" escape, which violates the overridden function’s promise`. That is meant: `tests/compilation/classEscapingParamOverride.emojic` has such an override commented out. But `🎍🥡` on the base method's parameter, which reads as the way to make the promise, is accepted and then written over by what the body does (`MFFunctionAnalyser::popScope`). So a class cannot be the extension point for anything that may keep what it is given. Instead: a protocol, whose methods promise nothing. |
| `42-range-counts-down.🍇` | `🆕⏩ 5 3❗️` gives 5 and 4: the initializer sets the step to -1 when the end is before the start (`s/⏩.🍇`), and its documentation says "from *start* to *stop*" and no more. So a loop over `🆕⏩ 0 count❗️` runs when a computed count is below zero, where most languages give nothing for such a range. |

## Seen in the source or in passing, and not shown by a program here

- **The mutex's try-lock**, `🔐 mutex❗️`, is declared to return a `👌`, and its native side
  (`sMutexTryLock`, `s/Thread.cpp`) is a `void` function that calls `try_lock()` and
  returns nothing. In this build the answer happens to be left in the register, and a
  program that asks a locked mutex and a free one gets the right answer both times.
- **The stock `files` package's read of a whole file** (`filesFileReadFile`,
  `files/File.cpp`) asks for the file's size, allocates that many bytes and only then
  looks whether anything failed. For a file that could not be opened the size is -1. We
  saw a missing file end a process while building; a program written for this page
  raised as it should, for a missing file and for a directory, so there is none.
- **The stock `json` parser leaks for every text it rejects**, about 240 bytes each. By
  reading, it is `24` above: its `🌕` returns a local from the middle, and the error
  exits of the `🔺` calls after it skip that local.
- **The help says that `-S` paths come after `./packages`.** `Compiler::searchPackage`
  looks in them first.
- **The emoji table predates Unicode 12.** A name such as 🪨 or 🧊 is read as part of a
  variable's name, and the error is about an identifier that was expected. This is #188,
  which is open; the message is what misleads.
- **Names the compiler keeps for itself give errors that do not say so.** A method
  called `⚖️`, called at the start of an expression, is `Unexpected token
  EndOfArguments` at the end of the line; `🔁` is `Expected Identifier but instead found
  RepeatWhile`; `📣` cannot name anything. `Compiler/Emojis.h` has the list.
