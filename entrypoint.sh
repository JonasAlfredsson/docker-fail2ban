#!/bin/sh

# When we get killed, kill all our children (o.O)
trap "exit" INT TERM
trap "kill 0" EXIT

# Source "util.sh" so we can have our nice tools
. $(cd $(dirname $0); pwd)/util.sh

# Collect custom environment variables or set defaults
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


# Init
echo "Initializing fail2ban container"
set_timezone
set_mail
set_config
copy_custom_jails
copy_custom_actions
copy_custom_filters
auto_enable_jails

# Launch fail2ban a child process
echo "Launching fail2ban"
exec "$@" &
FAIL2BAN_PID=$!

# fail2ban and the configuration file watcher processes are now our children. 
# As a parent we will wait for the PID of fail2ban, and if it exits we do the 
# same with its status code.
wait $FAIL2BAN_PID
exit $?
