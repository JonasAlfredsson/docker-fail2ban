#!/bin/sh

# Source "util.sh" which contain all our nice tools.
. $(cd $(dirname $0); pwd)/util.sh


# Collect custom environment variables or set defaults.
TZ=${TZ:-"Etc/UTC"}

IPTABLES_CHAIN=${IPTABLES_CHAIN:-"DOCKER-USER"}

F2B_LOG_LEVEL=${F2B_LOG_LEVEL:-"INFO"}
F2B_BAN_TIME=${F2B_BAN_TIME:-"600"}
F2B_FIND_TIME=${F2B_FIND_TIME:-"600"}
F2B_MAX_RETRY=${F2B_MAX_RETRY:-"5"}
F2B_DB_PURGE_AGE=${F2B_DB_PURGE_AGE:-"86400"}
F2B_DEST_EMAIL=${F2B_DEST_EMAIL:-"root@localhost"}
F2B_SENDER=${F2B_SENDER:-"fail2ban@$(hostname)"}
F2B_ACTION=${F2B_ACTION:-"%(action_mw)s"}

SSMTP_PORT=${SSMTP_PORT:-"25"}
SSMTP_HOSTNAME=${SSMTP_HOSTNAME:-"fail2ban"}
SSMTP_TLS=${SSMTP_TLS:-"YES"}


# Do all the initialization tasks.
echo "Initializing fail2ban container"
rm -rf /tmp/fail2ban.lock
set_timezone
set_iptables_chain
set_mail
set_fail2ban_config
set_default_jail_config
set_send_mail_only_when_ban_issued
symlink_files_to_folder "jail"
symlink_files_to_folder "action"
symlink_files_to_folder "filter"
auto_enable_jails


# Launch fail2ban.
echo "Launching fail2ban"
exec "$@"
