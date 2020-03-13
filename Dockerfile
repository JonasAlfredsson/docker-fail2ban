FROM alpine:3.8

LABEL maintainer="Jonas Alfredsson <jonas.alfredsson@protonmail.com>"

ARG FAIL2BAN_VERSION=0.10.4

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
    curl -L 'https://bootstrap.pypa.io/get-pip.py' | python3 \
    && \
# Install extra packages required by some features in fail2ban.
    pip3 install dnspython3 pyinotify \
# Download fail2ban.
    && cd /tmp \
    && curl -OL https://github.com/fail2ban/fail2ban/archive/${FAIL2BAN_VERSION}.zip \
    && unzip ${FAIL2BAN_VERSION}.zip \
    && cd fail2ban-${FAIL2BAN_VERSION} \
# Covert the fail2ban code to Python 3 and install it.
    && sh ./fail2ban-2to3 \
    && python3 setup.py install \
# Clean up temporary and unused files.
    && rm -f /etc/ssmtp/ssmtp.conf \
    && rm -rf /var/cache/apk/* /tmp/*

# Add our custom scripts and make them executable.
ADD *.sh /
RUN chmod a+x /*.sh

# Copy custom configurations.
COPY ./data /data

# Make database, containing ban history, persistent.
VOLUME [ "/fail2ban_db" ]

# Add heartbeat command.
HEALTHCHECK --interval=10s --timeout=5s CMD fail2ban-client ping

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "fail2ban-server", "-f", "-x", "-v", "start" ]
