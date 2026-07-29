ARG BASE_IMAGE=debian:bookworm-slim
FROM ${BASE_IMAGE}

# Shared setup
COPY shared/setup-root.sh /tmp/setup-root.sh
RUN bash /tmp/setup-root.sh

USER claude
COPY shared/setup-user.sh /tmp/setup-user.sh
RUN bash /tmp/setup-user.sh

# Sandbox plumbing lives outside /home/claude so the persistent home volume
# (which shadows /home/claude and only seeds from the image on first creation)
# can never make it stale — rebuilds always refresh these.
COPY --chmod=755 shared/runtime/tmux-picker.sh /opt/sandbox/tmux-picker.sh
COPY --chmod=755 shared/runtime/new-window.sh /opt/sandbox/new-window.sh
COPY --chmod=644 shared/config/tmux.conf /opt/sandbox/tmux.conf
COPY --chmod=644 shared/config/bashrc.append /opt/sandbox/bashrc.sh
COPY --chmod=755 --chown=claude:claude shared/runtime/entrypoint.sh /entrypoint.sh
COPY --chmod=755 shared/runtime/init.sh /init.sh

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
USER root
ENTRYPOINT ["/init.sh"]
