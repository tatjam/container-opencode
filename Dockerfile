FROM docker.io/library/node:20

ARG OPENCODE_VERSION=latest

# Install basic development tools, network utilities, build dependencies, and C/C++ LSP (clangd)
RUN apt-get update && apt-get install -y --no-install-recommends \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  python3 \
  python3-pip \
  python3-venv \
  build-essential \
  clangd \
  curl \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

ENV UV_LINK_MODE=copy \
    UV_TOOL_DIR=/usr/local/share/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && chown -R node:node /usr/local/share/npm-global

ARG USERNAME=node

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Fix messy permissions
RUN mkdir -p /workspace /home/node/.opencode \
  /home/node/.config/opencode \
  /home/node/.local/share/opencode \
  /home/node/.local/state/opencode && \
  chown -R node:node /workspace /home/node/.opencode /home/node/.config /home/node/.local

RUN mkdir -p /home/node/.cache/uv && chown -R node:node /home/node/.cache

RUN chmod 1777 /tmp /var/tmp

WORKDIR /workspace

# Install global Node & Python language servers
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin:/usr/local/go/bin:/home/node/.cargo/bin:/home/node/.elan/bin:/home/node/go/bin

RUN npm install -g \
  typescript-language-server \
  typescript \
  vscode-langservers-extracted \
  yaml-language-server

RUN uv tool install pyright

# Install Go
RUN GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n 1) && \
    curl -sSL "https://dl.google.com/go/${GO_VERSION}.linux-amd64.tar.gz" | tar -xz -C /usr/local

# Install OpenCode CLI
RUN npm install -g opencode-ai@${OPENCODE_VERSION}

# Allow passwordless sudo
RUN echo "$USERNAME ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
  && chmod 0440 /etc/sudoers.d/$USERNAME

# Set up non-root user context
USER node

# Install Rust & rust-analyzer via rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable && \
  /home/node/.cargo/bin/rustup component add rust-analyzer

# Install Lean4 via elan (Lean 4 binary acts natively as its own LSP server via `lean --server`)
RUN curl https://elan.lean-lang.org/elan-init.sh -sSf | sh -s -- -y --default-toolchain leanprover/lean4:stable

# Install Go language server (gopls)
RUN go install golang.org/x/tools/gopls@latest

CMD ["opencode"]
