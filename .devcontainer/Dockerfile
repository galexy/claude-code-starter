FROM debian:bookworm-slim

# Avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Create vscode user with UID 1000, passwordless sudo, zsh as default shell
RUN groupadd --gid 1000 vscode \
    && useradd --uid 1000 --gid 1000 -m -s /bin/zsh vscode \
    && apt-get update \
    && apt-get install -y --no-install-recommends sudo \
    && echo "vscode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode \
    && chmod 0440 /etc/sudoers.d/vscode

# Install base packages (not in slim image) and development tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    zsh \
    fzf \
    jq \
    less \
    man-db \
    procps \
    tmux \
    unzip \
    xz-utils \
    # Firewall and networking tools
    iptables \
    ipset \
    iproute2 \
    dnsutils \
    aggregate \
    # Needed for zsh-in-docker and general use
    locales \
    openssh-client \
    socat \
    && rm -rf /var/lib/apt/lists/*

# Generate locale
RUN sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8

# Install GitHub CLI from GitHub's apt repo
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI + Compose plugin from Docker's apt repo (CLI only, no daemon)
RUN apt-get update && apt-get install -y --no-install-recommends gnupg \
    && curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian bookworm stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Add vscode user to docker group for socket access
RUN groupadd -f docker && usermod -aG docker vscode

# Install Helix editor from GitHub releases
RUN ARCH=$(dpkg --print-architecture) \
    && HELIX_VERSION="25.01.1" \
    && case "$ARCH" in \
        amd64) HELIX_ARCH="x86_64" ;; \
        arm64) HELIX_ARCH="aarch64" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac \
    && curl -fsSL "https://github.com/helix-editor/helix/releases/download/${HELIX_VERSION}/helix-${HELIX_VERSION}-${HELIX_ARCH}-linux.tar.xz" \
        -o /tmp/helix.tar.xz \
    && tar -xf /tmp/helix.tar.xz -C /opt \
    && mv /opt/helix-${HELIX_VERSION}-${HELIX_ARCH}-linux /opt/helix \
    && ln -s /opt/helix/hx /usr/local/bin/hx \
    && rm /tmp/helix.tar.xz
ENV HELIX_RUNTIME=/opt/helix/runtime
ENV SHELL=/bin/zsh
ENV DEVCONTAINER=true

# Install git-delta for enhanced diffs
RUN ARCH=$(dpkg --print-architecture) \
    && DELTA_VERSION="0.18.2" \
    && curl -fsSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${ARCH}.deb" \
        -o /tmp/git-delta.deb \
    && dpkg -i /tmp/git-delta.deb \
    && rm /tmp/git-delta.deb

# Fetch fzf zsh integration scripts (not shipped in Debian bookworm's fzf package)
RUN mkdir -p /usr/share/doc/fzf/examples \
    && curl -fsSL https://raw.githubusercontent.com/junegunn/fzf/0.38.0/shell/key-bindings.zsh \
        -o /usr/share/doc/fzf/examples/key-bindings.zsh \
    && curl -fsSL https://raw.githubusercontent.com/junegunn/fzf/0.38.0/shell/completion.zsh \
        -o /usr/share/doc/fzf/examples/completion.zsh

# Install Node.js LTS (v22.x) from NodeSource, enable corepack for pnpm
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && corepack enable

# Install dolt
RUN curl -L https://github.com/dolthub/dolt/releases/latest/download/install.sh | bash

# Install beads (bd) issue tracker
RUN npm install -g @beads/bd

# Allow firewall script to run without password
COPY xdg-open /usr/local/bin/xdg-open
RUN chmod +x /usr/local/bin/xdg-open

COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh \
    && echo "vscode ALL=(ALL) NOPASSWD: /usr/local/bin/init-firewall.sh" >> /etc/sudoers.d/vscode

# Create workspace directory
RUN mkdir -p /workspace && chown vscode:vscode /workspace

# Switch to vscode user for remaining installs
USER vscode
WORKDIR /home/vscode

# Configure tmux for truecolor and zsh, with context window bar
RUN echo 'set -g default-terminal "tmux-256color"' > ~/.tmux.conf \
    && echo 'set -ag terminal-overrides ",xterm*:Tc"' >> ~/.tmux.conf \
    && echo 'set -g default-shell /bin/zsh' >> ~/.tmux.conf \
    && echo 'set -g status-right-length 60' >> ~/.tmux.conf \
    && echo 'set -g status-right "#(python3 /workspace/.claude/scripts/claude-context-bar.py --tmux) %H:%M"' >> ~/.tmux.conf \
    && echo 'set -g status-interval 10' >> ~/.tmux.conf

# Install zsh-in-docker (must run as vscode so config goes to /home/vscode)
RUN sh -c "$(curl -fsSL https://github.com/deluan/zsh-in-docker/releases/download/v1.2.1/zsh-in-docker.sh)" -- \
    -p git \
    -p fzf \
    -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
    -a "source /usr/share/doc/fzf/examples/completion.zsh" \
    -x

# Install uv (Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Claude Code via native installer (places binary in ~/.local/bin)
RUN curl -fsSL https://claude.ai/install.sh | bash

# Ensure ~/.local/bin is on PATH
ENV PATH="/home/vscode/.local/bin:${PATH}"

# Create .ssh directory
RUN mkdir /workspace/.ssh

WORKDIR /workspace
