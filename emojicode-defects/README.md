# Defects found in Emojicode 1.0 beta 2

These were found while building an HTTP server framework in Emojicode: some fifteen
thousand lines of it, and nearly as many of tests. Each defect has a short program here that
shows it and nothing else. None of them imports anything but the standard library and,
where the defect is theirs, the stock `files` and `json` packages.

- **The release**: `Emojicode-1.0-beta.2-Linux-x86_64` from the releases page, on Ubuntu
  22.04, run under emulation on an Apple Silicon Mac. Nothing here depends on that.
- **The source that is cited**: the repository a few commits after the tag
  (`v1.0-beta.2-21-g4dec45b4`).
- **To run them all**: `./run.sh`, where `emojicodec` is on the path. It builds and runs
  every program and compares what each did with what this page says: a compiler that
  fails, a program that crashes, a line of output, or memory that grows. It prints a
  line for each and ends with 0 when every defect is still there.
- **One program by hand**: `emojicodec 02-interpolation-beside-and.🍇 && ./02-interpolation-beside-and`.
  The two that need a package have a folder and a `build.sh`.

Each program begins with a comment that says what to expect and what happens instead.
"Instead" at the end of an entry is the spelling we use to stay clear of the defect,
which also shows how narrow each one is.

## How a leak is measured

A program in the third and fourth groups runs a loop a number of times that it names
in a line of its own (`200000 ➡️ rounds`). `run.sh` builds it as it is and with four
times the rounds, runs both, and reads the most resident memory each was seen to hold
from `/proc`. `20-steady.🍇` is the measurement's own check: a loop that makes a text in
every round and lets it go holds 6,480 kB at 200,000 rounds and at 800,000.

## The compiler

| Program | What it shows |
|---|---|
| `01-interpolated-element.🍇` | `🔤first: 🧲🐽 list 0❗️🧲🔤` makes the compiler print `Stored value type does not match pointer operand type!` and `Detected in: 🏁 (fn_1f3c1)`, which is LLVM's verifier refusing the code, and then **end with status 0**. The program it wrote is a segmentation fault at that line. The message is printed in `Compiler/Generation/FunctionCodeGenerator.cpp`; a build script cannot tell that anything went wrong without reading the output. Instead: hold the element in a variable first. |
| `02-interpolation-beside-and.🍇` | A call that is handed an interpolated text as one argument and a test with `🤝` in it as another, `👌 t 🔤a is 🧲a🧲🔤 a 🙌 3 🤝 b 🙌 5❗️`, is a segmentation fault when it runs. Either half alone is fine. Instead: put the test into a variable first. |
| `03-nan-compares-equal.🍇` | Comparisons of reals are compiled as LLVM's unordered ones (`FCmpUEQ`, `FCmpULT` and the rest, `Compiler/AST/ASTBinaryOperator_CG.cpp`), each of which is true when either side is a NaN. So a NaN is equal to 0.0, below it and above it, and equal to itself plus one. A loop that waits for a comparison to turn false never ends on one. |
| `04-real-with-exponent.🍇` | `2.5e3` does not compile: `Variable "e3" not defined`. The lexer ends the number at the `e`. |
| `05-fresh-object-of-later-class.🍇` | A fresh object of a class that is declared further down the file, handed straight to a method that only borrows it, aborts the compiler: `MFFlowCategory.hpp:31: … Assertion '!isUnknown()' failed`. `ASTInitialization::analyseMemoryFlow` asks whether the initializer keeps its object before the initializer has been analysed. A compiler built without assertions would read "unknown" as "does not escape" and put the object on the stack. Instead: bind the object to a variable first. |
| `06-optional-then-cast.🍇` | A value taken out of an optional `⚪️` with `↪️ … ➡️ value` and then cast with `🔲 value 🔡` aborts the compiler: `Type.hpp:346: … Assertion 'genericArguments_.front().type() != TypeType::Box' failed`. Instead: cast the optional itself. |
| `07-closure-in-a-small-function/` | A package has a method of two statements that lets its own object go and hands a closure which is not `🎍🥡` to a method that only calls it. The package compiles. A program that imports it does not: `🏛:12:12: error: Using non-escaping closure as escaping value`. Every function of two statements or fewer is written into the interface file with its body (`Function::isInline`), and this one is marked `🎍🥡` there. A function that is marked already is not analysed by the importing compile (`MFFunctionAnalyser::analyse` returns at once), so the closure in it is never given its place on the stack, and `ASTClosure::generate` then takes it for one that should have been escaping. With `🎍🥡` on the closure both compile, and the package's own compile warns `Using escaping closure as non-escaping value`. |
| `08-override-keeps-parameter.🍇` | A method that overrides another and keeps a parameter which the method it overrides only uses is refused: `Function lets parameter "line" escape, which violates the overridden function's promise`. Marking the parameter `🎍🥡` on the base method changes nothing: whether a parameter is kept is worked out from the body. So a class cannot be the extension point for anything that may keep what it is given. Instead: a protocol, whose methods promise nothing. |
| `44-package-link-order/` | A program imports a package that imports another. The link fails with `undefined reference` to the inner package's symbols: every package is put on the link line, but in an order in which a static archive that comes before the one which needs it is passed over. The compiler **ends with status 0** here too, though no program was linked. Instead: compile with `-c` and link by hand, with the archives between `-Wl,--start-group` and `-Wl,--end-group`. |

## Memory that is freed, or left on a dead frame, while it is in use

All five are segmentation faults.

| Program | What it shows |
|---|---|
| `10-reraise-hides-an-escape.🍇` | A new object held in a local and passed to a call wrapped in `🔺`, which keeps it, is gone when the function returns. The arguments of a call that is wrapped in `🔺` are not analysed (`ASTReraise::analyseMemoryFlow`), so the compiler never learns that the object leaves, and places it in the caller's frame. A `🆗` that binds no value has the same blind spot, and the stock `files` package can only be written to through such a call. Instead: `🆗 value call❗️ 🍇 … 🍉 🙅‍♀️ error 🍇 … 🍉`, where the call is made. |
| `11-returning-a-parameter.🍇` | `↩️ value`, where `value` is a parameter, returns it without retaining it, and the caller releases what it got as if it had been retained. With a temporary as the argument the text is freed while the caller holds it, and the next text that is made takes its place. Instead: `value ➡️ kept`, then `↩️ kept`. |
| `12-returning-self.🍇` | A setter that chains, ending in `↩️ 👇`, called on a fresh object: `💬 🆕🆘 404❗️ 🔤not here🔤❗️`. `MFFunctionAnalyser::recordThis` does not count a return as an escape, so the method is taken to borrow its object, the fresh object is placed in the caller's frame, and the method's result is that same object, gone when the caller returns it. Instead: `👇 ➡️ same`, then `↩️ same`. |
| `13-declared-after-a-handler.🍇` | A variable declared without a value (`🖍🆕 later 🔡`) further down a function that has handled an error with `🆗 … 🙅‍♀️` is assigned as if it already held an object. The handler's value and its error share a slot, slots are handed out again when a scope ends, and `finishMutualExclusiveBranches` (`Compiler/Analysis/PathAnalyser.cpp`) makes the slot "initialised" for good. The first assignment releases whatever the stack holds there. Instead: declare the variable before the `🆗`, or with a value. |
| `14-failed-cast-frees.🍇` | A cast that fails, handed straight to a call (`👀 🔲 thing 🎈❗️`), releases the object once for each failing cast. `ASTCast::downcast` (`Compiler/AST/ASTCast_CG.cpp`) releases the value in its failing branch on the assumption that it was retained, which is so only when the cast is bound. Instead: `↪️ 🔲 thing 🎈 ➡️ balloon 🍇`. |

## Memory that is never released

Measured as described above; the figures are from one run.

| Program | What it shows | Held after 200,000 rounds, and after 800,000 |
|---|---|---|
| `21-interpolation-leaks.🍇` | An interpolated text leaks the text form of every value it inserts. Instead: join a list, `🆕🔡 🍿 a b 🍆 🔤🔤❗️`. | 24,872 kB and 119,152 kB |
| `22-return-in-else.🍇` | A `↩️` directly inside a plain `🙅 🍇` block releases none of the function's locals. `ASTIf::analyseMemoryFlow` (`Compiler/AST/ASTControlFlow.cpp`) never pops the scope of the else block. Instead: `🙅↪️ 👍 🍇 ↩️ … 🍉`. | 23,400 kB and 89,864 kB |
| `23-variable-in-else.🍇` | A variable declared directly inside a plain `🙅 🍇` block is never released, for the same reason. | 35,892 kB and 149,752 kB |
| `24-returning-a-local-early.🍇` | `↩️ name` from the middle of a function marks the variable's slot as returned. The mark is never cleared, so every way out after it skips that variable. Instead: a local is returned by the last statement only. | 35,160 kB and 146,868 kB |
| `25-new-list-over-a-variable.🍇` | `🆕🍨🐚🔡🍆❗️ ➡️ 🖍list` over a list builds the new one in place without releasing the old (`ASTVariableInit::generate`, `Compiler/AST/ASTVariables_CG.cpp`). The same for a dictionary. Instead: empty the list with `🐗`. | 120,360 kB and 527,468 kB |
| `26-return-in-unsafe-block.🍇` | A `↩️` directly inside a `☣️` block releases none of the function's locals either: such a block has no scope of its own to pop. Instead: hand the value out of the block and return it after. | 24,960 kB and 93,848 kB |

## The standard library and the stock packages

| Program | What it shows |
|---|---|
| `30-data-slice-leaks.🍇` | `🔪` on `📇` leaks on every call (47,552 kB after 800,000 rounds, where the steady program holds 6,480). The method returns from inside a `☣️` block: `26` above, in the library itself. |
| `31-data-join-leaks.🍇` | `➕` on `📇` likewise (97,740 kB after 800,000 rounds). |
| `32-text-split-leaks.🍇` | `🔫` on `🔡` likewise (403,632 kB after 800,000 rounds of a text split in eight). |
| `33-dictionary-leaks.🍇` | A dictionary leaks an entry whenever two keys share a bucket: 100,000 dictionaries of eight keys, each made and let go, leave 80,020 kB behind, and 400,000 leave 317,296 kB. The hash of a text is seeded at random when the process starts, so the figure changes from run to run, and a test for leaks passes and fails by turns. |
| `34-lower-case-overflows.🍇` | `📪` and `📫` allocate exactly as many bytes as the text has and write the converted letters without a bound. `Ⱥ` (U+023A) is two bytes and its lower-case form three, so a text of them overruns: `malloc(): corrupted top size`, and the process aborts. |
| `35-bytes-taken-for-text.🍇` | `🔡 data❗️` returns a text for the bytes `FF FE`. Its documentation says that no value is returned for bytes that are not UTF-8. |
| `36-lowest-integer-as-text.🍇` | `🔡 n 10❗️` for -9223372036854775808 gives twenty bytes of memory that it never wrote to. |
| `37-trim-cuts-a-character.🍇` | `🔧` on `🔤Port Hermes to 🍇🔤`, which has nothing to trim, gives back 16 bytes of its 19: the last character is cut in the middle. |
| `39-thread-let-go.🍇` | A `🧵` whose last reference is dropped before it was joined aborts the process when the thread object is released: `terminate called without an active exception`. |
| `41-last-of-an-empty-list.🍇` | `🐼` on an empty list lowers the count to -1 and reads the memory in front of the list. Its documentation says that no value is returned. A segmentation fault here. |
| `43-json-without-a-depth.🍇` | The stock `json` parser calls itself once for every `[` and has no limit: 200,000 of them run the stack out, and the process ends where a 🚧🔸🌸 was to be raised. |

## A question

`42-range-counts-down.🍇`: `🆕⏩ 5 3❗️` gives 5 and 4, so a loop over `🆕⏩ 0 count❗️` runs
when the count is below zero. That may be meant. It is easy to step into when the count
was computed, and most languages give nothing for such a range.

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
- **A value from the stock `json` parser, cast to a dictionary and then released**, was a
  double free in our code (`🔲 value 🍯🐚⚪️🍆`), and the parser left about 240 bytes
  behind for each text it rejected. We replaced the parser before writing these
  programs and did not go back to isolate either.
- **The emoji table predates Unicode 12.** A name such as 🪨 or 🧊 is read as part of a
  variable's name, and the error is about an identifier that was expected. That is an
  old table and no defect, but the message does not say so.
- **Names the compiler keeps for itself give errors that do not say so.** A method
  called `⚖️`, called at the start of an expression, is `Unexpected token
  EndOfArguments` at the end of the line; `🔁` is `Expected Identifier but instead found
  RepeatWhile`; `📣` cannot name anything. `Compiler/Emojis.h` has the list.
