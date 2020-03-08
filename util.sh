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


# Configure mail settings.
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


# Modify the fail2ban config file and the default jail settings.
set_config() {
  echo "Setting Fail2ban configuration"
  sed -i "s/logtarget =.*/logtarget = STDOUT/g" /etc/fail2ban/fail2ban.conf
  sed -i "s/loglevel =.*/loglevel = $F2B_LOG_LEVEL/g" /etc/fail2ban/fail2ban.conf
  sed -i "s/dbfile =.*/dbfile = \/fail2ban_db\/fail2ban\.sqlite3/g" /etc/fail2ban/fail2ban.conf
  sed -i "s/dbpurgeage =.*/dbpurgeage = $F2B_DB_PURGE_AGE/g" /etc/fail2ban/fail2ban.conf
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


# A function which creates symlinks inside the default fail2ban folders, under
# /etc/fail2ban/, to all files found in the user defined folders under /data/.
# This will allow us to manipulate the created symlinks, without destroying
# anything for the user.
symlink_files_to_folder() {
  type=$1
  echo "Checking for ${type}s in /data/${type}.d..."
  files=$(ls -l /data/${type}.d/ | egrep '^-' | awk '{print $9}')

  if [ "${files}x" == "x" ]; then
    echo "  No ${type} files found"
    return
  fi

  for file in ${files}; do
    if [ -f "/etc/fail2ban/${type}.d/${file}" ]; then
      echo "  WARNING: '${file}' already exists and will be overridden"
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


# Given a config file path, return 0 if the referenced log file exist (or there
# are no file needed to be found). Return 1 otherwise (i.e. error exit code).
logfile_exist() {
  logfile=$(parse_logfile $1)
  if [ ! -f $logfile ]; then
      #error "Could not find $logfile for $1"
      return 1
  fi
  return 0
}


# To hinder that many processes spam fail2ban with restart requests, at the
# same time, we make a simple locking mechanism to create some order in this
# world. `mkdir` should be an atomic operation.
reload_fail2ban() {
  while :; do
    if mkdir /tmp/restart.lock; then
      # We have lock, restart the fail2ban server.
      fail2ban-client reload
      sleep 2
      rmdir /tmp/restart.lock
      break
    else
      # Some other process has the restart lock, wait a second.
      sleep 1
    fi
  done
}


# This is a function which can be "attached" to jail config files that are
# disabled because they reference a log file which does not (yet) exist. The
# service who will produce this log file might just not have started yet, so
# here we will monitor for changes of these missing log files every 30 seconds
# and then re-enable the config files if they show up.
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


# A function that sifts through /data/jail.d/ and disables every jail config
# file which references a log file that does not (yet) exist. It then starts a
# "config_watcher" on each one of these configs, which were not ready, to be
# able to re-enable them when their log files shows up.
auto_enable_jails() {
  echo "Auto enabling all jails..."
  conf_files=$(ls -l /etc/fail2ban/jail.d/ | egrep '^(-|l).*\.conf.*' | awk '{print $9}')
  for conf_file in "/etc/fail2ban/jail.d/${conf_files}"; do
    if logfile_exist $conf_file; then
      if [ ${conf_file##*.} = nolog ]; then
        echo "Found the log file for ${conf_file}, enabling..."
        mv $conf_file ${conf_file%.*}
      fi
    else
      if [ ${conf_file##*.} = conf ]; then
        error "The log file for ${conf_file} is missing, disabling..."
        mv $conf_file $conf_file.nolog
        conf_file="$conf_file.nolog"
      fi

      echo "Attaching a watcher to $conf_file"
      config_watcher $conf_file &
    fi
  done
}
