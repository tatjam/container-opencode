# syntax=docker/dockerfile:1

# ---- Node/Python LSPs, uv, OpenCode CLI ----
FROM docker.io/library/node:20 AS node-tools

ARG OPENCODE_VERSION=latest

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global \
    UV_LINK_MODE=copy \
    UV_TOOL_DIR=/usr/local/share/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/share/uv-tools/bin

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

RUN mkdir -p /usr/local/share/npm-global && chown -R node:node /usr/local/share/npm-global

RUN npm install -g typescript-language-server
RUN npm install -g typescript
RUN npm install -g vscode-langservers-extracted
RUN npm install -g yaml-language-server
RUN uv tool install pyright
RUN npm install -g opencode-ai@${OPENCODE_VERSION}

# ---- Rust + rust-analyzer ----
FROM docker.io/library/node:20 AS rust
USER node
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
RUN /home/node/.cargo/bin/rustup component add rust-analyzer

# ---- Go + gopls ----
FROM docker.io/library/node:20 AS golang
RUN GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n 1) && \
    curl -sSL "https://dl.google.com/go/${GO_VERSION}.linux-amd64.tar.gz" | tar -xz -C /usr/local
USER node
ENV PATH=/usr/local/go/bin:$PATH
RUN go install golang.org/x/tools/gopls@latest

# ---- Lean4 via elan (Lean 4 binary acts natively as its own LSP server via `lean --server`) ----
FROM docker.io/library/node:20 AS lean
USER node
RUN curl https://elan.lean-lang.org/elan-init.sh -sSf | sh -s -- -y --default-toolchain leanprover/lean4:stable

# ---- Julia via juliaup ----
FROM docker.io/library/node:20 AS julia
USER node
RUN curl -fsSL https://install.julialang.org | sh -s -- -y

# ---- aven task manager ----
FROM docker.io/library/node:20 AS aven
USER node
RUN curl -fsSL https://raw.githubusercontent.com/raine/aven/main/scripts/install | bash
RUN /home/node/.local/bin/aven update --yes

# ---- Nim + nimlangserver ----
FROM docker.io/library/node:20 AS nim
RUN apt-get update && apt-get install -y --no-install-recommends git \
  && apt-get clean && rm -rf /var/lib/apt/lists/*
USER node
# nimble/nim write linker args and other temp files into the CWD,
# so it must be writable by node
WORKDIR /home/node
RUN curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y
ENV PATH=/home/node/.nimble/bin:$PATH
RUN nimble install -g nimlangserver

########################################
# Final image: system packages first (rarely change), then cheap
# COPY layers from the stages above.
########################################
FROM docker.io/library/node:20

# System packages, one layer per dep so unchanged ones stay cached
RUN apt-get update

RUN apt-get install -y --no-install-recommends git
RUN apt-get install -y --no-install-recommends procps
RUN apt-get install -y --no-install-recommends sudo
RUN apt-get install -y --no-install-recommends fzf
RUN apt-get install -y --no-install-recommends zsh
RUN apt-get install -y --no-install-recommends man-db
RUN apt-get install -y --no-install-recommends unzip
RUN apt-get install -y --no-install-recommends gnupg2
RUN apt-get install -y --no-install-recommends gh
RUN apt-get install -y --no-install-recommends iptables
RUN apt-get install -y --no-install-recommends iproute2
RUN apt-get install -y --no-install-recommends dnsutils
RUN apt-get install -y --no-install-recommends aggregate
RUN apt-get install -y --no-install-recommends jq
RUN apt-get install -y --no-install-recommends python3 python3-pip python3-venv
RUN apt-get install -y --no-install-recommends build-essential
RUN apt-get install -y --no-install-recommends clangd
RUN apt-get install -y --no-install-recommends curl

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Toolchains and tools from the stages above
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
COPY --from=node-tools /usr/local/share/npm-global /usr/local/share/npm-global
COPY --from=node-tools /usr/local/share/uv-tools /usr/local/share/uv-tools
COPY --from=node-tools /usr/local/share/uv-tools/bin/ /usr/local/bin/
COPY --from=rust /home/node/.cargo /home/node/.cargo
COPY --from=rust /home/node/.rustup /home/node/.rustup
COPY --from=golang /usr/local/go /usr/local/go
COPY --from=golang /home/node/go /home/node/go
COPY --from=lean /home/node/.elan /home/node/.elan
COPY --from=julia /home/node/.juliaup /home/node/.juliaup
COPY --from=aven /home/node/.local /home/node/.local
COPY --from=nim /home/node/.choosenim /home/node/.choosenim
COPY --from=nim /home/node/.nimble /home/node/.nimble

ENV DEVCONTAINER=true \
    NPM_CONFIG_PREFIX=/usr/local/share/npm-global \
    UV_LINK_MODE=copy \
    UV_TOOL_DIR=/usr/local/share/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin
ENV PATH=$PATH:/usr/local/share/npm-global/bin:/usr/local/go/bin:/home/node/.cargo/bin:/home/node/.elan/bin:/home/node/go/bin:/home/node/.juliaup/bin:/home/node/.local/bin:/home/node/.nimble/bin

# Fix messy permissions
RUN mkdir -p /workspace /home/node/.opencode \
  /home/node/.config/opencode \
  /home/node/.local/share/opencode \
  /home/node/.local/state/opencode \
  /home/node/.cache/uv && \
  chown -R node:node /workspace /home/node/.opencode /home/node/.config /home/node/.local /home/node/.cache && \
  chown -R node:node /usr/local/share/uv-tools && \
  chown node:node /usr/local/bin

RUN chmod 1777 /tmp /var/tmp

ARG USERNAME=node

# Allow passwordless sudo
RUN echo "$USERNAME ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
  && chmod 0440 /etc/sudoers.d/$USERNAME

WORKDIR /workspace

USER node

CMD ["opencode", "--auto"]
