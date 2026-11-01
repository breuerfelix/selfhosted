FROM restic/restic:0.19.1

USER root

# The official restic image is Alpine-based. docker-cli is required by the
# pre/post backup lifecycle script to stop and restart the selected containers.
RUN apk add --no-cache docker-cli tzdata

ENV TZ=Europe/Berlin \
    RESTIC_CACHE_DIR=/tmp/restic-cache

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 common.sh /usr/local/lib/restic-backup-common.sh
COPY --chmod=0755 backup.sh /usr/local/bin/backup.sh
COPY --chmod=0755 prune.sh /usr/local/bin/prune.sh
COPY --chmod=0755 check.sh /usr/local/bin/check.sh
COPY --chmod=0644 crontab /etc/crontabs/root

RUN ln -snf /usr/share/zoneinfo/Europe/Berlin /etc/localtime \
    && printf '%s\n' Europe/Berlin > /etc/timezone

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
