FROM alpine:3.8

LABEL maintainer="Jonas Alfredsson <jonas.alfredsson@protonmail.com>"

ARG FAIL2BAN_VERSION=0.10.4

# Create necessary folders
RUN mkdir -p /xlogs /fail2ban_db /data/action.d /data/filter.d /data/jail.d \
    && chmod 777 /xlogs

# Download and install fail2ban
RUN apk --update --no-cache add \
    curl iptables python3 python3-dev py-setuptools ssmtp tzdata whois ncurses \
    && cd /tmp \
    && curl -OL https://github.com/fail2ban/fail2ban/archive/${FAIL2BAN_VERSION}.zip \
    && unzip ${FAIL2BAN_VERSION}.zip \
    && cd fail2ban-${FAIL2BAN_VERSION} \
    && python setup.py install \
    && rm -rf /etc/fail2ban/jail.d \
    && rm -f /etc/ssmtp/ssmtp.conf \
    && rm -rf /var/cache/apk/* /tmp/*

# Add custom scritps and make them executable
ADD *.sh /
RUN chmod a+x /*.sh

# Copy custom configurations
COPY ./data /data

# Make database, containing ban history, persistent 
VOLUME [ "/fail2ban_db" ]

# Add heartbeat command
HEALTHCHECK --interval=10s --timeout=5s CMD fail2ban-client ping

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "fail2ban-server", "-f", "-x", "-v", "start" ]

