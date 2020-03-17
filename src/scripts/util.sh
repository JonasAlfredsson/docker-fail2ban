#!/bin/sh

# Helper function to output error messages to STDERR, with red text.
error() {
  (set +x; tput -Tscreen bold
  tput -Tscreen setaf 1
  echo $*
  tput -Tscreen sgr0) >&2
}


# Set timezone inside container.
set_timezone() {
  echo "Setting timezone to ${TZ}"
  ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime
  echo ${TZ} > /etc/timezone
}


# Edit the line that defines which CHAIN banned IPs should be attached to.
set_iptables_chain() {
  echo "Configuring fail2ban to use the '${IPTABLES_CHAIN}' CHAIN"
  sed -i "s/chain =.*/chain = ${IPTABLES_CHAIN}/g" /etc/fail2ban/action.d/iptables-common.conf
}

# Configure mail settings.
set_mail() {
  echo "Setting SSMTP configuration"
  if [ -z "$SSMTP_HOST" ] ; then
    echo "  SSMTP_HOST unset, defaulting to sending mails to localhost"
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


# Modify the fail2ban config file.
set_fail2ban_config() {
  echo "Setting Fail2ban configuration"
  sed -i "s/logtarget =.*/logtarget = STDOUT/g" /etc/fail2ban/fail2ban.conf
  sed -i "s/loglevel =.*/loglevel = $F2B_LOG_LEVEL/g" /etc/fail2ban/fail2ban.conf
  sed -i "s/dbfile =.*/dbfile = \/fail2ban_db\/fail2ban\.sqlite3/g" /etc/fail2ban/fail2ban.conf
  sed -i "s/dbpurgeage =.*/dbpurgeage = $F2B_DB_PURGE_AGE/g" /etc/fail2ban/fail2ban.conf
}


# Create the jail.local file to define the default settings for jails.
set_default_jail_config() {
  cat > /etc/fail2ban/jail.local <<EOL
[DEFAULT]
bantime = ${F2B_BAN_TIME}
findtime = ${F2B_FIND_TIME}
maxretry = ${F2B_MAX_RETRY}
destemail = ${F2B_DEST_EMAIL}
sender = ${F2B_SENDER}
action = ${F2B_ACTION}
EOL
}


# Create a `.local` file, which will have precedence over the `.conf` file, to
# make so that fail2ban only sends a mail when a ban is issued, and not for all
# the other actions (which gets annoying).
set_send_mail_only_when_ban_issued() {
  cat > /etc/fail2ban/action.d/sendmail-common.local <<EOL
[Definition]
actionstart =
actionstop =
EOL
}


# A function which creates symlinks inside the default fail2ban folders, under
# /etc/fail2ban/, to all files found in the user defined folders under /data/.
# This will allow us to manipulate the created symlinks, without destroying
# anything for the user.
symlink_files_to_folder() {
  type=$1
  echo "Checking for ${type}s in /data/${type}.d..."
  files=$(ls -l /data/${type}.d/ 2>/dev/null | egrep '^-' | awk '{print $9}')

  if [ "${files}x" == "x" ]; then
    echo "  No ${type} files found"
    return
  fi

  for file in ${files}; do
    if [ -f "/etc/fail2ban/${type}.d/${file}" ]; then
      if [ ! -h "/etc/fail2ban/${type}.d/${file}" ]; then
        echo "  WARNING: '${file}' already exists and will be overwritten"
      fi
      rm -f "/etc/fail2ban/${type}.d/${file}"
    fi
    echo "  Adding ${type} '${file}'"
    ln -sf "/data/${type}.d/${file}" "/etc/fail2ban/${type}.d/"
  done
}


# Return the path of the log file specified in a jail config file.
parse_logfile() {
  grep "logpath" "$1" | cut -d '=' -f 2
}


# Return the name of the filter specified in a jail config file.
parse_filter_name() {
  grep "filter" "$1" | cut -d '=' -f 2
}


# Given a config file path, return 0 if the referenced log file exist (or there
# are no file needed to be found). Return 1 otherwise (i.e. error exit code).
logfile_exist() {
  logfile=$(parse_logfile $1)
  if [ ! -f $logfile ]; then
    return 1
  fi
  return 0
}


# Given a config file path, return 0 if the referenced filter exist, otherwise
# we will return 1 (i.e. error exit code).
filter_exist() {
  filter_name=$(parse_filter_name $1)
  if [ "${filter_name}x" == "x" ]; then
    error "There is no filter referenced in $1"
    return 1
  fi

  filter_file=$(ls -l /etc/fail2ban/filter.d/ | egrep "^(-|l).*${filter_name}\.(conf|local).*" | awk '{print $9}')
  if [ ! -f "/etc/fail2ban/filter.d/${filter_file}" ]; then
    error "The filter referenced in $1 was not found"
    return 1
  fi
  return 0
}


# This is a function which can be "attached" to a jail config file that is
# disabled because it reference a log file which does not (yet) exist. The
# service that is responsible for writing to this log file might just not have
# started yet, so here we will monitor for changes of this missing log file
# every 30 seconds and then re-enable the config file if/when the log shows up.
config_watcher() {
  local conf_file=$1
  sleep 5 # Do not immediately check again.
  while :; do
    if logfile_exist ${conf_file}; then
      # To hinder that multiple processes (i.e. config_watchers) perform changes
      # at the same time, we make a simple locking mechanism to create some
      # order in this world.
      while :; do
        # NOTE: `mkdir` should be an atomic operation.
        if mkdir /tmp/fail2ban.lock 2>/dev/null ; then
          # We have the lock, rename the config restart the fail2ban server.
          echo "Found the log file for ${conf_file}, enabling..."
          mv ${conf_file} ${conf_file%.*}

          echo "Reloading fail2ban"
          fail2ban-client reload
          sleep 1

          rmdir /tmp/fail2ban.lock
          break
        else
          # Some other process has the lock, wait 2 seconds and try again.
          sleep 2
        fi
      done
      break
    fi

    error "Waiting for the log file referenced in ${conf_file%.*} to come online"
    sleep 30
  done
}


# A function that sifts through /data/jail.d/ and disables every jail config
# file which reference a log file that does not (yet) exist. It then starts a
# `config_watcher` for each one of these configs, which were not ready, to be
# able to re-enable them when their log files shows up.
auto_enable_jails() {
  echo "Auto enabling all jails..."
  critical_errors=0

  conf_files=$(ls -l /etc/fail2ban/jail.d/ | egrep '^(-|l).*\.conf.*' | awk '{print "/etc/fail2ban/jail.d/"$9}')
  for conf_file in ${conf_files}; do
    if ! filter_exist $conf_file; then
      critical_errors=$((critical_errors+1))
    elif logfile_exist $conf_file; then
      if [ ${conf_file##*.} = nolog ]; then
        echo "Found the log file for ${conf_file}, enabling..."
        mv ${conf_file} ${conf_file%.*}
      fi
    else
      if [ ${conf_file##*.} = conf ]; then
        echo "The log file for ${conf_file} is missing, disabling..."
        mv ${conf_file} ${conf_file}.nolog
        conf_file="${conf_file}.nolog"
      fi

      echo "Attaching a watcher to $conf_file"
      config_watcher $conf_file &
    fi
  done

  if [ "$critical_errors" -ne "0" ]; then
    error "There are critical errors with the config files; aborting..."
    exit 1
  fi
}
