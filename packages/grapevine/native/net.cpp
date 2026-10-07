// Grapevine's socket shim: the syscalls Emojicode's standard library does not reach.
// Syscalls only. Nothing in this file knows what HTTP is.
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
#include <cstring>
#include <ctime>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <string>
#include <sys/random.h>
#include <sys/socket.h>
#include <unistd.h>

namespace {

const runtime::Integer statusOk = 0;
const runtime::Integer statusTimeout = 1;
const runtime::Integer statusClosed = 2;
const runtime::Integer statusFailed = 3;

thread_local runtime::Integer lastReadStatus = statusOk;
std::atomic<int> stopRequested{0};

// The key every table of names in the process is hashed with: 128 bits from the system's
// random source. If the system gives none, the key stays zero. Tables still work then; a
// client could only work out which names fall into the same slot.
struct HashKey {
    uint64_t halves[2] = {0, 0};

    HashKey() {
        auto* bytes = reinterpret_cast<unsigned char*>(halves);
        size_t have = 0;
        while (have < sizeof(halves)) {
            const ssize_t got = getrandom(bytes + have, sizeof(halves) - have, 0);
            if (got < 0) {
                if (errno == EINTR) continue;
                break;
            }
            have += static_cast<size_t>(got);
        }
        if (have == sizeof(halves)) return;
        // A kernel older than getrandom, or a sandbox that forbids it.
        FILE* source = std::fopen("/dev/urandom", "rb");
        if (source == nullptr) return;
        have += std::fread(bytes + have, 1, sizeof(halves) - have, source);
        std::fclose(source);
    }
};

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

extern "C" runtime::Integer gvHashKey(runtime::ClassInfo*, runtime::Integer half) {
    // Drawn once, the first time it is asked for. C++ runs this initializer on one thread
    // only, however many ask at once.
    static const HashKey key;
    return static_cast<runtime::Integer>(key.halves[half & 1]);
}

extern "C" void gvLine(runtime::ClassInfo*, s::String* text) {
    // The line and its end go out in one write. Two writes, which is what the standard
    // library's print does, let a line from another thread land between them.
    std::string line = text->stdString();
    line.push_back('\n');
    size_t done = 0;
    while (done < line.size()) {
        const ssize_t written = write(STDOUT_FILENO, line.data() + done, line.size() - done);
        if (written < 0) {
            if (errno == EINTR) continue;
            return;
        }
        done += static_cast<size_t>(written);
    }
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
