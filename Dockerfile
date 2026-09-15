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
  build-essential \
  clangd \
  curl \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash history
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/node/.opencode && \
  chown -R node:node /workspace /home/node/.opencode

WORKDIR /workspace

# Install global Node & Python language servers
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin:/usr/local/go/bin:/usr/local/go/bin:/home/node/.cargo/bin:/home/node/.elan/bin

RUN npm install -g \
  typescript-language-server \
  typescript \
  vscode-langservers-extracted \
  yaml-language-server

RUN pip3 install --no-cache-dir pyright --break-system-packages || pip3 install --no-cache-dir pyright

# Install Go
RUN GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n 1) && \
    curl -sSL "https://dl.google.com/go/${GO_VERSION}.linux-amd64.tar.gz" | tar -xz -C /usr/local

# Install OpenCode CLI
RUN npm install -g opencode-ai@${OPENCODE_VERSION}

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
