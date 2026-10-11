// Grapevine's shim: the syscalls Emojicode's standard library does not reach, for sockets
// first, and for the few other things only the system can say: the time of day, what a file
// holds, random bits, the names in the environment, its words for an error number. What
// the system says and nothing more. Nothing in this file knows what HTTP is.
//
// Every function is bound to a type method of the Emojicode class 🔩 (see net.🍇), so each
// takes the class info pointer first. Arguments are borrowed; a returned object belongs to
// the caller. Nothing here throws or raises: failures come back as status codes.

#include "runtime/Runtime.h"
#include "s/String.h"
#include "s/Data.h"

#include <arpa/inet.h>
#include <atomic>
#include <cerrno>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <dirent.h>
#include <fcntl.h>
#include <malloc.h>
#include <mutex>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <string>
#include <sys/random.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {

const runtime::Integer statusOk = 0;
const runtime::Integer statusTimeout = 1;
const runtime::Integer statusClosed = 2;
const runtime::Integer statusFailed = 3;

const runtime::Integer fileRead = 0;
const runtime::Integer fileMissing = 1;
const runtime::Integer fileUnreadable = 2;
const runtime::Integer fileTooLarge = 3;

thread_local runtime::Integer lastReadStatus = statusOk;
thread_local runtime::Integer lastFileStatus = fileRead;
// What the last look at a path found, for the thread that looked.
thread_local runtime::Integer lastLookSize = 0;
thread_local runtime::Integer lastLookModifiedMs = 0;
std::atomic<int> stopRequested{0};

// Fills *bytes* from the system's random source. Says whether it gave them all.
bool fillRandom(unsigned char* bytes, size_t size) {
    size_t have = 0;
    while (have < size) {
        const ssize_t got = getrandom(bytes + have, size - have, 0);
        if (got < 0) {
            if (errno == EINTR) continue;
            break;
        }
        have += static_cast<size_t>(got);
    }
    if (have == size) return true;
    // A kernel older than getrandom, or a sandbox that forbids it.
    FILE* source = std::fopen("/dev/urandom", "rb");
    if (source == nullptr) return false;
    have += std::fread(bytes + have, 1, size - have, source);
    std::fclose(source);
    return have == size;
}

// The key every table of names in the process is hashed with: 128 bits from the system's
// random source. If the system gives none, the key stays zero. Tables still work then; a
// client could only work out which names fall into the same slot.
struct HashKey {
    uint64_t halves[2] = {0, 0};

    HashKey() { fillRandom(reinterpret_cast<unsigned char*>(halves), sizeof(halves)); }
};

// Writes *text* and a line break to *fd*, one line at a time for the whole process. A
// single write is whole only up to PIPE_BUF bytes (4,096) when the descriptor is a pipe,
// and a request line with a long path is longer than that, so without the lock two
// workers' lines cut into each other. The lock is here and not in a logger because every
// logger in the process shares the descriptor.
void writeLine(int fd, s::String* text) {
    static std::mutex oneLineAtATime;
    std::string line = text->stdString();
    line.push_back('\n');
    const std::lock_guard<std::mutex> turn(oneLineAtATime);
    size_t done = 0;
    while (done < line.size()) {
        const ssize_t written = write(fd, line.data() + done, line.size() - done);
        if (written >= 0) {
            done += static_cast<size_t>(written);
            continue;
        }
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            // Whoever shares the descriptor made it non-blocking. Wait for room, as a
            // blocking one would: giving up here drops the line without a trace.
            pollfd room{fd, POLLOUT, 0};
            if (poll(&room, 1, -1) < 0 && errno != EINTR) return;
            continue;
        }
        return;
    }
}

runtime::Integer wallMs() {
    timespec now{};
    clock_gettime(CLOCK_REALTIME, &now);
    return static_cast<runtime::Integer>(now.tv_sec) * 1000 + now.tv_nsec / 1000000;
}

runtime::Integer nowMs() {
    timespec now{};
    clock_gettime(CLOCK_MONOTONIC, &now);
    return static_cast<runtime::Integer>(now.tv_sec) * 1000 + now.tv_nsec / 1000000;
}

int pollTimeout(runtime::Integer ms) {
    if (ms < 0) return 0;
    if (ms > 3600000) return 3600000;
    return static_cast<int>(ms);
}

s::Data* makeData(const char* bytes, runtime::Integer count) {
    auto data = s::Data::init();
    data->data = runtime::allocate<runtime::Byte>(count > 0 ? count : 1);
    if (count > 0) std::memcpy(data->data.get(), bytes, static_cast<size_t>(count));
    data->count = count;
    return data;
}

addrinfo* resolve(s::String* host, runtime::Integer port, int flags) {
    if (port < 0 || port > 65535) return nullptr;
    addrinfo hints{};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = flags | AI_NUMERICHOST | AI_NUMERICSERV;
    addrinfo* found = nullptr;
    const std::string service = std::to_string(port);
    if (getaddrinfo(host->stdString().c_str(), service.c_str(), &hints, &found) != 0) return nullptr;
    return found;
}

void setBlocking(int fd, bool blocking) {
    const int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) return;
    fcntl(fd, F_SETFL, blocking ? (flags & ~O_NONBLOCK) : (flags | O_NONBLOCK));
}

void onStopSignal(int) {
    // A second signal means the first one was not enough: leave at once.
    if (stopRequested.exchange(1) != 0) _exit(1);
}

}  // namespace

extern "C" runtime::Integer gvListen(runtime::ClassInfo*, s::String* host, runtime::Integer port,
                                     runtime::Integer backlog) {
    addrinfo* address = resolve(host, port, AI_PASSIVE);
    if (address == nullptr) return -EINVAL;
    const int fd = socket(address->ai_family, address->ai_socktype, address->ai_protocol);
    if (fd < 0) {
        const int error = errno;
        freeaddrinfo(address);
        return -error;
    }
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    const int queue = backlog < 1 ? 1 : (backlog > 65535 ? 65535 : static_cast<int>(backlog));
    if (bind(fd, address->ai_addr, address->ai_addrlen) != 0 || listen(fd, queue) != 0) {
        const int error = errno;
        freeaddrinfo(address);
        close(fd);
        return -error;
    }
    freeaddrinfo(address);
    // Several workers poll one listener. When a client arrives they all wake and only one
    // accept can win, so the others must get "nothing to accept" instead of blocking.
    setBlocking(fd, false);
    return fd;
}

extern "C" runtime::Integer gvPort(runtime::ClassInfo*, runtime::Integer fd) {
    sockaddr_storage address{};
    socklen_t length = sizeof(address);
    if (getsockname(static_cast<int>(fd), reinterpret_cast<sockaddr*>(&address), &length) != 0) return -1;
    if (address.ss_family == AF_INET) return ntohs(reinterpret_cast<sockaddr_in*>(&address)->sin_port);
    if (address.ss_family == AF_INET6) return ntohs(reinterpret_cast<sockaddr_in6*>(&address)->sin6_port);
    return -1;
}

extern "C" runtime::Integer gvAccept(runtime::ClassInfo*, runtime::Integer fd, runtime::Integer timeoutMs) {
    pollfd waiting{static_cast<int>(fd), POLLIN, 0};
    const int ready = poll(&waiting, 1, pollTimeout(timeoutMs));
    if (ready == 0) return -1;
    if (ready < 0) return errno == EINTR ? -1 : -2;
    if ((waiting.revents & POLLNVAL) != 0) return -2;
    const int client = accept(static_cast<int>(fd), nullptr, nullptr);
    if (client < 0) {
        const int error = errno;
        if (error == EAGAIN || error == EWOULDBLOCK || error == EINTR || error == ECONNABORTED) return -1;
        return -2;
    }
    // Timeouts on a connection come from poll, so the socket itself must block.
    setBlocking(client, true);
    int yes = 1;
    setsockopt(client, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof(yes));
    return client;
}

extern "C" runtime::Boolean gvPending(runtime::ClassInfo*, runtime::Integer fd) {
    pollfd waiting{static_cast<int>(fd), POLLIN, 0};
    return poll(&waiting, 1, 0) > 0 && (waiting.revents & POLLIN) != 0;
}

extern "C" runtime::Integer gvConnect(runtime::ClassInfo*, s::String* host, runtime::Integer port,
                                      runtime::Integer timeoutMs) {
    addrinfo* address = resolve(host, port, 0);
    if (address == nullptr) return -EINVAL;
    const int fd = socket(address->ai_family, address->ai_socktype, address->ai_protocol);
    if (fd < 0) {
        const int error = errno;
        freeaddrinfo(address);
        return -error;
    }
    setBlocking(fd, false);
    int error = 0;
    if (connect(fd, address->ai_addr, address->ai_addrlen) != 0) {
        error = errno;
        if (error == EINPROGRESS) {
            pollfd waiting{fd, POLLOUT, 0};
            if (poll(&waiting, 1, pollTimeout(timeoutMs)) <= 0) {
                error = ETIMEDOUT;
            } else {
                socklen_t length = sizeof(error);
                if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) != 0) error = errno;
            }
        }
    }
    freeaddrinfo(address);
    if (error != 0) {
        close(fd);
        return -error;
    }
    setBlocking(fd, true);
    int yes = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof(yes));
    return fd;
}

extern "C" s::Data* gvRead(runtime::ClassInfo*, runtime::Integer fd, runtime::Integer max,
                           runtime::Integer timeoutMs) {
    char buffer[65536];
    size_t want = sizeof(buffer);
    if (max < 1) want = 1;
    else if (max < static_cast<runtime::Integer>(sizeof(buffer))) want = static_cast<size_t>(max);

    pollfd waiting{static_cast<int>(fd), POLLIN, 0};
    const int ready = poll(&waiting, 1, pollTimeout(timeoutMs));
    if (ready == 0) {
        lastReadStatus = statusTimeout;
        return makeData(nullptr, 0);
    }
    if (ready < 0) {
        lastReadStatus = errno == EINTR ? statusTimeout : statusFailed;
        return makeData(nullptr, 0);
    }
    if ((waiting.revents & POLLNVAL) != 0) {
        lastReadStatus = statusFailed;
        return makeData(nullptr, 0);
    }
    const ssize_t got = recv(static_cast<int>(fd), buffer, want, 0);
    if (got > 0) {
        lastReadStatus = statusOk;
        return makeData(buffer, got);
    }
    if (got == 0) {
        lastReadStatus = statusClosed;
    } else if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) {
        lastReadStatus = statusTimeout;
    } else if (errno == ECONNRESET || errno == EPIPE) {
        lastReadStatus = statusClosed;
    } else {
        lastReadStatus = statusFailed;
    }
    return makeData(nullptr, 0);
}

extern "C" runtime::Integer gvStatus(runtime::ClassInfo*) {
    return lastReadStatus;
}

extern "C" runtime::Integer gvWrite(runtime::ClassInfo*, runtime::Integer fd, s::Data* data,
                                    runtime::Integer timeoutMs) {
    const char* bytes = data->data.get();
    size_t left = data->count > 0 ? static_cast<size_t>(data->count) : 0;
    while (left > 0) {
        // Never block inside send: the wait for a slow peer happens in poll, where it is timed.
        const ssize_t sent = send(static_cast<int>(fd), bytes, left, MSG_DONTWAIT | MSG_NOSIGNAL);
        if (sent > 0) {
            bytes += sent;
            left -= static_cast<size_t>(sent);
            continue;
        }
        if (sent < 0 && errno == EINTR) continue;
        if (sent < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            pollfd waiting{static_cast<int>(fd), POLLOUT, 0};
            const int ready = poll(&waiting, 1, pollTimeout(timeoutMs));
            if (ready == 0) return statusTimeout;
            if (ready < 0 && errno != EINTR) return statusFailed;
            if (ready > 0 && (waiting.revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) return statusClosed;
            continue;
        }
        if (sent < 0 && (errno == EPIPE || errno == ECONNRESET)) return statusClosed;
        return statusFailed;
    }
    return statusOk;
}

extern "C" void gvClose(runtime::ClassInfo*, runtime::Integer fd, runtime::Integer lingerMs) {
    if (fd < 0) return;
    if (lingerMs > 0) {
        // Closing with unread input makes the kernel send a reset, which can destroy a
        // response the peer has not read yet. So: say we are done, let the peer finish
        // talking for a bounded time, and only then close.
        shutdown(static_cast<int>(fd), SHUT_WR);
        const runtime::Integer deadline = nowMs() + lingerMs;
        char scratch[4096];
        for (;;) {
            const runtime::Integer left = deadline - nowMs();
            if (left <= 0) break;
            pollfd waiting{static_cast<int>(fd), POLLIN, 0};
            if (poll(&waiting, 1, pollTimeout(left)) <= 0) break;
            if (recv(static_cast<int>(fd), scratch, sizeof(scratch), MSG_DONTWAIT) <= 0) break;
        }
    }
    close(static_cast<int>(fd));
}

extern "C" s::String* gvPeer(runtime::ClassInfo*, runtime::Integer fd) {
    sockaddr_storage address{};
    socklen_t length = sizeof(address);
    char text[NI_MAXHOST] = "";
    if (getpeername(static_cast<int>(fd), reinterpret_cast<sockaddr*>(&address), &length) == 0) {
        if (getnameinfo(reinterpret_cast<sockaddr*>(&address), length, text, sizeof(text), nullptr, 0,
                        NI_NUMERICHOST) != 0) {
            text[0] = '\0';
        }
    }
    return s::String::init(text);
}

extern "C" runtime::Integer gvNowMs(runtime::ClassInfo*) {
    return nowMs();
}

extern "C" runtime::Integer gvResidentKb(runtime::ClassInfo*) {
    // Linux reports the resident set in pages as the second field of /proc/self/statm.
    FILE* statm = std::fopen("/proc/self/statm", "r");
    if (statm == nullptr) return -1;
    long total = 0;
    long resident = 0;
    const int fields = std::fscanf(statm, "%ld %ld", &total, &resident);
    std::fclose(statm);
    if (fields != 2) return -1;
    return static_cast<runtime::Integer>(resident) * (sysconf(_SC_PAGESIZE) / 1024);
}

extern "C" s::Data* gvReadFile(runtime::ClassInfo*, s::String* path, runtime::Integer max) {
    const std::string name = path->stdString();
    // The C library would stop at a zero byte and open some other file than the one named.
    if (name.find('\0') != std::string::npos) {
        lastFileStatus = fileMissing;
        return makeData(nullptr, 0);
    }
    const int fd = open(name.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        lastFileStatus = (errno == ENOENT || errno == ENOTDIR) ? fileMissing : fileUnreadable;
        return makeData(nullptr, 0);
    }
    struct stat info {};
    // Only a regular file: a folder cannot be read, and a pipe or a device might never end.
    if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode)) {
        close(fd);
        lastFileStatus = fileUnreadable;
        return makeData(nullptr, 0);
    }
    const size_t limit = max > 0 ? static_cast<size_t>(max) : 0;
    std::string bytes;
    char buffer[65536];
    for (;;) {
        const ssize_t got = read(fd, buffer, sizeof(buffer));
        if (got < 0) {
            if (errno == EINTR) continue;
            close(fd);
            lastFileStatus = fileUnreadable;
            return makeData(nullptr, 0);
        }
        if (got == 0) break;
        // Counted as it is read, not taken from the size: a file can grow while it is open.
        if (bytes.size() + static_cast<size_t>(got) > limit) {
            close(fd);
            lastFileStatus = fileTooLarge;
            return makeData(nullptr, 0);
        }
        bytes.append(buffer, static_cast<size_t>(got));
    }
    close(fd);
    lastFileStatus = fileRead;
    return makeData(bytes.data(), static_cast<runtime::Integer>(bytes.size()));
}

extern "C" runtime::Integer gvFileStatus(runtime::ClassInfo*) {
    return lastFileStatus;
}

extern "C" runtime::Integer gvLook(runtime::ClassInfo*, s::String* path) {
    lastLookSize = 0;
    lastLookModifiedMs = 0;
    const std::string name = path->stdString();
    // The C library would stop at a zero byte and look at some other path than the one named.
    if (name.empty() || name.find('\0') != std::string::npos) return 0;
    struct stat info {};
    if (stat(name.c_str(), &info) != 0) return 0;
    lastLookModifiedMs = static_cast<runtime::Integer>(info.st_mtim.tv_sec) * 1000
        + static_cast<runtime::Integer>(info.st_mtim.tv_nsec / 1000000);
    if (S_ISREG(info.st_mode)) {
        // A file this process may not read is, to it, not a file that can be served: asked
        // of the system as the user the process acts as, which is the one an open goes by.
        if (faccessat(AT_FDCWD, name.c_str(), R_OK, AT_EACCESS) != 0) {
            lastLookModifiedMs = 0;
            return 0;
        }
        lastLookSize = static_cast<runtime::Integer>(info.st_size);
        return 1;
    }
    return S_ISDIR(info.st_mode) ? 2 : 3;
}

extern "C" runtime::Integer gvLookSize(runtime::ClassInfo*) {
    return lastLookSize;
}

extern "C" runtime::Integer gvLookModifiedMs(runtime::ClassInfo*) {
    return lastLookModifiedMs;
}

extern "C" s::String* gvRealPath(runtime::ClassInfo*, s::String* path) {
    const std::string name = path->stdString();
    if (name.empty() || name.find('\0') != std::string::npos) return s::String::init("");
    char* resolved = realpath(name.c_str(), nullptr);
    if (resolved == nullptr) return s::String::init("");
    s::String* text = s::String::init(resolved);
    free(resolved);
    return text;
}

extern "C" runtime::Integer gvOpenFile(runtime::ClassInfo*, s::String* path) {
    const std::string name = path->stdString();
    if (name.find('\0') != std::string::npos) return -ENOENT;
    // Without waiting: opening a pipe that nobody writes to would otherwise never come back.
    const int fd = open(name.c_str(), O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOCTTY);
    if (fd < 0) return -errno;
    struct stat info {};
    // Only a regular file, as above: a folder cannot be read, and a pipe or a device might never end.
    if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode)) {
        close(fd);
        return S_ISDIR(info.st_mode) ? -EISDIR : -EINVAL;
    }
    return fd;
}

extern "C" s::Data* gvReadAt(runtime::ClassInfo*, runtime::Integer fd, runtime::Integer offset,
                             runtime::Integer max) {
    if (max <= 0) {
        lastFileStatus = fileRead;
        return makeData(nullptr, 0);
    }
    if (fd < 0 || offset < 0) {
        lastFileStatus = fileUnreadable;
        return makeData(nullptr, 0);
    }
    // No caller asks for more than a piece of a file at a time, and nothing here should
    // be able to ask for a buffer of any size it likes.
    const size_t want = max > 1048576 ? 1048576 : static_cast<size_t>(max);
    std::string bytes(want, '\0');
    size_t got = 0;
    // A read may come back short before the end of the file. Only a read of nothing is the end.
    while (got < want) {
        const ssize_t now = pread(static_cast<int>(fd), &bytes[got], want - got,
                                  static_cast<off_t>(offset) + static_cast<off_t>(got));
        if (now < 0) {
            if (errno == EINTR) continue;
            lastFileStatus = fileUnreadable;
            return makeData(nullptr, 0);
        }
        if (now == 0) break;
        got += static_cast<size_t>(now);
    }
    lastFileStatus = fileRead;
    return makeData(bytes.data(), static_cast<runtime::Integer>(got));
}

extern "C" void gvCloseFile(runtime::ClassInfo*, runtime::Integer fd) {
    if (fd >= 0) close(static_cast<int>(fd));
}

extern "C" runtime::Integer gvOpenCount(runtime::ClassInfo*) {
    DIR* entries = opendir("/proc/self/fd");
    if (entries == nullptr) return -1;
    runtime::Integer count = 0;
    while (const dirent* entry = readdir(entries)) {
        if (entry->d_name[0] != '.') count++;
    }
    closedir(entries);
    // The folder that was just read was itself open while it was counted.
    return count - 1;
}

extern "C" runtime::Integer gvWallMs(runtime::ClassInfo*) {
    return wallMs();
}

extern "C" runtime::Integer gvHashKey(runtime::ClassInfo*, runtime::Integer half) {
    // Drawn once, the first time it is asked for. C++ runs this initializer on one thread
    // only, however many ask at once.
    static const HashKey key;
    return static_cast<runtime::Integer>(key.halves[half & 1]);
}

extern "C" runtime::Integer gvHeapBytes(runtime::ClassInfo*) {
    // What is allocated and not yet freed, from the allocator's own books: its main arena,
    // which is where the thread that started the process allocates, and the large blocks it
    // maps one by one. Unlike the resident set, this does not stay up after memory is freed,
    // so it shows a leak however much room earlier work left behind.
    const struct mallinfo2 info = mallinfo2();
    return static_cast<runtime::Integer>(info.uordblks) + static_cast<runtime::Integer>(info.hblkhd);
}

extern "C" void gvLine(runtime::ClassInfo*, s::String* text) {
    writeLine(STDOUT_FILENO, text);
}

extern "C" void gvErrorLine(runtime::ClassInfo*, s::String* text) {
    writeLine(STDERR_FILENO, text);
}

extern "C" runtime::Integer gvRandom(runtime::ClassInfo*) {
    // Fresh from the system every time, not from a generator seeded once: these bits are
    // shown to clients as request IDs, and one ID must not give away the next.
    uint64_t bits = 0;
    if (!fillRandom(reinterpret_cast<unsigned char*>(&bits), sizeof(bits))) {
        // No random source at all. The least an ID has to be is different from the last.
        static std::atomic<uint64_t> drawn{0};
        bits = (static_cast<uint64_t>(wallMs()) << 20) ^ (static_cast<uint64_t>(getpid()) << 44) ^ drawn.fetch_add(1);
    }
    return static_cast<runtime::Integer>(bits);
}

extern "C" s::String* gvErrorText(runtime::ClassInfo*, runtime::Integer code) {
    char buffer[256];
    // The GNU form of strerror_r: it returns the text, and need not have used the buffer.
    return s::String::init(strerror_r(static_cast<int>(code), buffer, sizeof(buffer)));
}

extern "C" runtime::Boolean gvIsAddress(runtime::ClassInfo*, s::String* host) {
    // Asked of the same function the listener resolves with, so the two cannot disagree.
    addrinfo* found = resolve(host, 0, AI_PASSIVE);
    if (found == nullptr) return false;
    freeaddrinfo(found);
    return true;
}

extern "C" s::String* gvLookup(runtime::ClassInfo*, s::String* host) {
    addrinfo hints{};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    addrinfo* found = nullptr;
    if (getaddrinfo(host->stdString().c_str(), nullptr, &hints, &found) != 0) return s::String::init("");
    // One listener binds one address. The first IPv4 one, since that is where a client that
    // is given the same name and no more is most likely to look; IPv6 when there is no other.
    const addrinfo* chosen = nullptr;
    for (const addrinfo* each = found; each != nullptr; each = each->ai_next) {
        if (each->ai_family == AF_INET) {
            chosen = each;
            break;
        }
        if (each->ai_family == AF_INET6 && chosen == nullptr) chosen = each;
    }
    char text[NI_MAXHOST] = "";
    if (chosen != nullptr
        && getnameinfo(chosen->ai_addr, chosen->ai_addrlen, text, sizeof(text), nullptr, 0, NI_NUMERICHOST) != 0) {
        text[0] = '\0';
    }
    freeaddrinfo(found);
    return s::String::init(text);
}

extern "C" runtime::Integer gvVariableCount(runtime::ClassInfo*) {
    runtime::Integer count = 0;
    while (environ != nullptr && environ[count] != nullptr) count++;
    return count;
}

extern "C" s::String* gvVariableName(runtime::ClassInfo*, runtime::Integer index) {
    if (index < 0 || environ == nullptr) return s::String::init("");
    // Walked from the start, so that an index past the end is found out and not read.
    runtime::Integer at = 0;
    while (environ[at] != nullptr && at < index) at++;
    if (environ[at] == nullptr) return s::String::init("");
    const char* entry = environ[at];
    const char* equals = std::strchr(entry, '=');
    const std::string name = equals == nullptr ? std::string(entry) : std::string(entry, equals);
    return s::String::init(name.c_str());
}

extern "C" void gvExitNow(runtime::ClassInfo*, runtime::Integer code) {
    // Not exit(): that runs the C library's cleanup, which waits for locks that a worker
    // stuck in a handler may hold for ever. Leaving at once is the point.
    _exit(static_cast<int>(code));
}

extern "C" void gvTrapSignals(runtime::ClassInfo*) {
    struct sigaction action {};
    action.sa_handler = onStopSignal;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, nullptr);
    sigaction(SIGINT, &action, nullptr);
    std::signal(SIGPIPE, SIG_IGN);
}

extern "C" runtime::Boolean gvStopRequested(runtime::ClassInfo*) {
    return stopRequested.load() != 0;
}
