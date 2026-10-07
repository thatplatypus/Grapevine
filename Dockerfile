# Reproducible Grapevine build. Emojicode only ships x86_64 binaries, so on Apple
# Silicon this runs under emulation:
#   docker build -t grapevine .
#   docker run --rm -p 8080:8080 grapevine            # serve the Todo API
#   docker run --rm grapevine ./build.sh test         # run both test suites
FROM --platform=linux/amd64 ubuntu:22.04

# libtinfo5 is the one library the prebuilt compiler needs that newer distros dropped.
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential curl ca-certificates libtinfo5 \
 && rm -rf /var/lib/apt/lists/*

ARG EMOJICODE=1.0-beta.2
RUN curl -fsSL "https://github.com/emojicode/emojicode/releases/download/v${EMOJICODE}/Emojicode-${EMOJICODE}-Linux-x86_64.tar.gz" \
    | tar -xz -C /opt \
 && cd "/opt/Emojicode-${EMOJICODE}-Linux-x86_64" \
 && cp emojicodec /usr/local/bin/ \
 && mkdir -p /usr/local/EmojicodePackages /usr/local/include/emojicode \
 && cp -r packages/* /usr/local/EmojicodePackages/ \
 && cp -r include/* /usr/local/include/emojicode/

WORKDIR /src
COPY . .
RUN ./build.sh

ENV PORT=8080
EXPOSE 8080
# Line-buffer stdout so the request log shows up in `docker logs` as it happens.
CMD ["stdbuf", "-oL", "./build/bin/todo-api"]
