ARG NANOBOT_BASE=nanobot-upstream:local
FROM ${NANOBOT_BASE}

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends gh build-essential file procps \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -o nanobot -g nanobot /home/linuxbrew/.linuxbrew "$HOME/.cache/Homebrew" \
    && chown -R nanobot:nanobot /home/nanobot

USER nanobot
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH" \
    HOMEBREW_NO_ANALYTICS=1

RUN curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o /tmp/install-homebrew.sh \
    && NONINTERACTIVE=1 bash /tmp/install-homebrew.sh \
    && rm /tmp/install-homebrew.sh \
    && brew install summarize \
    && brew cleanup --prune=all

ENV NANOBOT_TOOLS__EXEC__PATH_APPEND=/home/linuxbrew/.linuxbrew/bin
