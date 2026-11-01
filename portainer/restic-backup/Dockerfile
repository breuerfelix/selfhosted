FROM restic/restic:0.19.1

USER root

# The official restic image is Alpine-based. docker-cli is required by the
# pre/post backup lifecycle script to stop and restart the selected containers.
RUN apk add --no-cache docker-cli tzdata ca-certificates \
    && wget -q https://dl.k8s.io/release/v1.36.5/bin/linux/amd64/kubectl -O /usr/local/bin/kubectl \
    && echo '33bc88a24c3b09cf55bfd59e6ca977881b61fc3f25ab65bc80c65b430248648e  /usr/local/bin/kubectl' | sha256sum -c - \
    && chmod 0755 /usr/local/bin/kubectl

ENV TZ=Europe/Berlin \
    RESTIC_CACHE_DIR=/tmp/restic-cache

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 common.sh /usr/local/lib/restic-backup-common.sh
COPY --chmod=0755 papra-kubernetes.sh /usr/local/lib/papra-kubernetes.sh
COPY --chmod=0755 backup.sh /usr/local/bin/backup.sh
COPY --chmod=0755 prune.sh /usr/local/bin/prune.sh
COPY --chmod=0755 check.sh /usr/local/bin/check.sh
COPY --chmod=0644 crontab /etc/crontabs/root

RUN ln -snf /usr/share/zoneinfo/Europe/Berlin /etc/localtime \
    && printf '%s\n' Europe/Berlin > /etc/timezone

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
