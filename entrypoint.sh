#!/bin/sh

TZ=${TZ:-"UTC"}

F2B_LOG_LEVEL=${F2B_LOG_LEVEL:-"INFO"}
F2B_DB_PURGE_AGE=${F2B_DB_PURGE_AGE:-"1d"}
F2B_MAX_RETRY=${F2B_MAX_RETRY:-"5"}
F2B_DEST_EMAIL=${F2B_DEST_EMAIL:-"root@localhost"}
F2B_SENDER=${F2B_SENDER:-"root@fail2ban"}
F2B_ACTION=${F2B_ACTION:-"%(action_mw)s"}

SSMTP_PORT=${SSMTP_PORT:-"25"}
SSMTP_HOSTNAME=${SSMTP_HOSTNAME:-"fail2ban"}
SSMTP_TLS=${SSMTP_TLS:-"YES"}


# Set timezone inside container
set_timezone() {
  echo "Setting timezone to ${TZ}"
  ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime
  echo ${TZ} > /etc/timezone
}


# Configure mail settings
set_mail() {
  echo "Setting SSMTP configuration"
  if [ -z "$SSMTP_HOST" ] ; then
    echo "WARNING: SSMTP_HOST must be defined if you want fail2ban to send emails"
    cat > /etc/ssmtp/ssmtp.conf <<EOL
root=postmaster
mailhub=localhost:25
hostname=${SSMTP_HOSTNAME}
FromLineOverride=YES
EOL
  else
    cat > /etc/ssmtp/ssmtp.conf <<EOL
mailhub=${SSMTP_HOST}:${SSMTP_PORT}
hostname=${SSMTP_HOSTNAME}
FromLineOverride=YES
AuthUser=${SSMTP_USER}
AuthPass=${SSMTP_PASSWORD}
UseTLS=${SSMTP_TLS}
UseSTARTTLS=${SSMTP_TLS}
EOL
  fi
  unset SSMTP_HOST
  unset SSMTP_USER
  unset SSMTP_PASSWORD
}


# Modify the fail2ban config file
set_config() {
  echo "Setting Fail2ban configuration"
  sed -i "s/logtarget =.*/logtarget = STDOUT/g" /etc/fail2ban/fail2ban.conf
  sed -i "s/loglevel =.*/loglevel = $F2B_LOG_LEVEL/g" /etc/fail2ban/fail2ban.conf
  sed -i "s/dbfile =.*/dbfile = \/fail2ban_db\/fail2ban\.sqlite3/g" /etc/fail2ban/fail2ban.conf
  sed -i "s/dbpurgeage =.*/dbpurgeage = $F2B_DB_PURGE_AGE/g" /etc/fail2ban/fail2ban.conf
  cat > /etc/fail2ban/jail.local <<EOL
[DEFAULT]
maxretry = ${F2B_MAX_RETRY}
destemail = ${F2B_DEST_EMAIL}
sender = ${F2B_SENDER}
action = ${F2B_ACTION}
EOL
}


# Copy any custom jails to correct location
copy_custom_jails() {
  echo "Copying custom jails"
  ln -sf /data/jail.d /etc/fail2ban/
}


# Check if there are any custom actions and copy them to correct location
copy_custom_actions() {
  echo "Checking for custom actions in /data/action.d..."
  actions=$(ls -l /data/action.d | egrep '^-' | awk '{print $9}')
  for action in ${actions}; do
    if [ -f "/etc/fail2ban/action.d/${action}" ]; then
      echo "  WARNING: '${action}'' already exists and will be overridden"
      rm -f "/etc/fail2ban/action.d/${action}"
    fi
    echo "  Add custom action '${action}''"
    ln -sf "/data/action.d/${action}" "/etc/fail2ban/action.d/"
  done
}


# Check if there are any custom filters and copy them to correct location
copy_custom_filters() {
  echo "Checking for custom filters in /data/filter.d..."
  filters=$(ls -l /data/filter.d | egrep '^-' | awk '{print $9}')
  for filter in ${filters}; do
    if [ -f "/etc/fail2ban/filter.d/${filter}" ]; then
      echo "  WARNING: '${filter}' already exists and will be overridden"
      rm -f "/etc/fail2ban/filter.d/${filter}"
    fi
    echo "  Add custom filter '${filter}'"
    ln -sf "/data/filter.d/${filter}" "/etc/fail2ban/filter.d/"
  done
}


# Init
echo "Initializing fail2ban container"
set_timezone
set_mail
set_config
copy_custom_jails
copy_custom_actions
copy_custom_filters

echo "Launching fail2ban"
exec "$@"
