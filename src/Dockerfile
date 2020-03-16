FROM alpine:3.11

LABEL maintainer="Jonas Alfredsson <jonas.alfredsson@protonmail.com>"

ARG FAIL2BAN_VERSION=0.11.1

# Do a single run command to make the intermediary containers smaller.
RUN \
# Create necessary folders.
    mkdir -p \
    /xlogs \
    /fail2ban_db \
    /data/action.d \
    /data/filter.d \
    /data/jail.d \
    && \
    chmod 777 /xlogs \
    && \
# Install all necessary packages.
    apk --update --no-cache add \
        curl \
        iptables \
        ncurses \
        python3 \
        python3-dev \
        ssmtp \
        tzdata \
        whois \
    && \
# Install pip and setuptools.
    cd /tmp \
    && \
    curl -L 'https://bootstrap.pypa.io/get-pip.py' -o get-pip.py \
    && \
    python3 get-pip.py --no-wheel \
    && \
# Install extra packages required by some features in fail2ban.
    pip3 install --compile \
        dnspython3 \
        pyinotify \
    && \
# Download fail2ban.
    curl -OL https://github.com/fail2ban/fail2ban/archive/${FAIL2BAN_VERSION}.zip \
    && \
    unzip ${FAIL2BAN_VERSION}.zip \
    && \
    cd fail2ban-${FAIL2BAN_VERSION} \
    && \
# Covert the fail2ban code to Python 3 and install it.
    sh ./fail2ban-2to3 \
    && \
    python3 setup.py install --optimize=2 \
    && \
# Clean up programs and files which will not be used anymore.
    python3 -m pip uninstall -y pip setuptools \
    && \
    apk del python3-dev \
    && \
    rm -f /etc/ssmtp/ssmtp.conf \
    && \
    rm -rf /var/cache/apk/* /tmp/*

# Add our custom scripts and make them executable.
COPY scripts/ /scripts
RUN chmod -R a+x /scripts

# Make database, containing ban history, persistent.
VOLUME [ "/fail2ban_db" ]

# Add heartbeat command.
HEALTHCHECK --interval=10s --timeout=5s CMD fail2ban-client ping || exit 1

ENTRYPOINT [ "/scripts/entrypoint.sh" ]
CMD [ "fail2ban-server", "-f", "-x", "-v", "start" ]
