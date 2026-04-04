ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# Shared setup
COPY shared/setup-root.sh /tmp/setup-root.sh
RUN bash /tmp/setup-root.sh

USER claude
COPY shared/setup-user.sh /tmp/setup-user.sh
RUN bash /tmp/setup-user.sh

COPY --chmod=755 --chown=claude:claude shared/tmux-picker.sh /home/claude/tmux-picker.sh
COPY --chmod=755 --chown=claude:claude shared/entrypoint.sh /entrypoint.sh

# Environment-specific setup
ARG ENV_NAME
RUN mkdir -p /tmp/env
COPY environments/${ENV_NAME}/ /tmp/env/
USER root
RUN [ -f /tmp/env/setup-root.sh ] && bash /tmp/env/setup-root.sh || true
USER claude
RUN [ -f /tmp/env/setup-user.sh ] && bash /tmp/env/setup-user.sh || true

ENV PATH="/home/claude/.local/bin:${PATH}"
ENV LANG=C.utf8

WORKDIR /workspace
EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
