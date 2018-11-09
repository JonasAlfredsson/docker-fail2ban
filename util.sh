#!/bin/sh

# Helper function to output error messages to STDERR, with red text
error() {
    (set +x; tput -Tscreen bold
    tput -Tscreen setaf 1
    echo $*
    tput -Tscreen sgr0) >&2
}


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


# Link entire custom jail folder to correct location
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


# Return the specified path of the log file
parse_logfile() {
    grep "logpath" "$1" | cut -d '=' -f 2 
}


# Given a config file path, return 0 if the referenced log file exist (or there 
# are no file needed to be found). Return 1 otherwise.
logfile_exist() {
    logfile=$(parse_logfile $1)
    if [ ! -f $logfile ]; then
        #error "Could not find $logfile for $1"
        return 1
    fi
    return 0
}


# To hinder that many processes spam the client with restart requests at the 
# same we make a simple locking mechanism to create some order in this world.
reload_fail2ban() {
    while :; do
        if mkdir /tmp/restart.lock; then
            # We have lock, restart the fail2ban server
            fail2ban-client restart
            rmdir /tmp/restart.lock
            break
        else
            # Some other process has the restart lock, wait a second
            sleep 1
        fi
    done
}


# A function that will disable every config file that has a misspelled log file
# path, or the service who will produce this log file might just not have 
# started yet. This will will monitor for changes every 30 seconds and then 
# re-enable them if the missing log file shows up.
config_watcher() {
    conf_file=$1
    while :; do
        if logfile_exist $conf_file; then
            if [ ${conf_file##*.} = nolog ]; then
                echo "Found the log file for $conf_file, enabling..."
                mv $conf_file ${conf_file%.*}
            fi
            echo "Reloading fail2ban"
            reload_fail2ban
            break
        fi
        error "Waiting for the log file referenced in $conf_file to come online"
        sleep 30
    done
}


# A function that sifts through /data/jail.d/, looking for jail configuration 
# files and starts a "config_watcher" on each one of them.
auto_enable_jails() {
    for conf_file in /data/jail.d/*.conf*; do
        if logfile_exist $conf_file; then
            if [ ${conf_file##*.} = nolog ]; then
                echo "Found the log file for $conf_file, enabling..."
                mv $conf_file ${conf_file%.*}
            fi
        else
            if [ ${conf_file##*.} = conf ]; then
                error "The log file for $conf_file is missing, disabling..."
                mv $conf_file $conf_file.nolog
                conf_file="$conf_file.nolog"
            fi

            echo "Attaching a watcher to $conf_file"
            config_watcher $conf_file &
        fi
    done
}
