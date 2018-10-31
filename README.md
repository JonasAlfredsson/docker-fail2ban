
# docker-fail2ban

This Alpine based Docker image runs [fail2ban][1] on the
host's network with privileges to edit the [iptables][4]. Create custom 
"filters" and "jails" to block spam and brute-force attacks before they hit your
other containers. 

# Acknowledgments and Thanks

This repository was forked from `@crazymax` to be able to modify it so that it
fit better into my setup. If you are interested, [check out his][2] other 
Docker images!

# Usage

## Run with `docker run`

This container thrives the best while in a docker-compose setup, but can also 
launched stand-alone by running the two following commands:
```bash
build --tag crazymax/fail2ban:latest .
docker run -d --network host --cap-add NET_ADMIN --cap-add NET_RAW \
  --name fail2ban \
  -v $(pwd)/data:/data \
  -v /var/log:/var/log:ro \
  crazymax/fail2ban:latest
```

## Run with `docker-compose`

Docker-compose is the recommended way to run this image. See the example of a 
compose file inside the `examples` folder, and you may use the `.env` file to 
not have all the variables in a separate location. Then it can all be launched 
via the following commands:
```bash
docker-compose build --pull
docker-compose up
```

## Notes

### Example with sshd jail

Create a new "jail" file called `sshd.conf` in `$(pwd)/jail.d`:
```
[sshd]
enabled     = true
port        = ssh
filter      = sshd[mode=aggressive]
logpath     = /var/log/auth.log
maxretry    = 5
```

And start the container with more verbose output.
```bash
docker run -it --network host --cap-add NET_ADMIN --cap-add NET_RAW \
  --name fail2ban \
  -v $(pwd)/data:/data \
  -v /var/log:/var/log:ro \
  -e F2B_LOG_LEVEL=DEBUG \
  crazymax/fail2ban:latest
```

Here is the log output if an IP is banned.
```
...
2018-04-25 00:07:21,003 fail2ban.filterpoll     [1]: DEBUG   /var/log/auth.log has been modified
2018-04-25 00:07:21,007 fail2ban.filter         [1]: DEBUG   Processing line with time:1524607640.0 and ip:198.51.100.0
2018-04-25 00:07:21,007 fail2ban.filter         [1]: INFO    [sshd] Found 198.51.100.0 - 2018-04-25 00:07:20
2018-04-25 00:07:21,008 fail2ban.failmanager    [1]: DEBUG   Total # of detected failures: 5. Current failures from 1 IPs (IP:count): 198.51.100.0:5
2018-04-25 00:07:21,407 fail2ban.actions        [1]: NOTICE  [sshd] Ban 198.51.100.0
2018-04-25 00:07:21,410 fail2ban.action         [1]: DEBUG   iptables -w -N f2b-sshd
iptables -w -A f2b-sshd -j RETURN
iptables -w -I INPUT -p tcp -m multiport --dports 22 -j f2b-sshd
2018-04-25 00:07:21,464 fail2ban.utils          [1]: DEBUG   7f6c759a3c00 -- returned successfully 0
2018-04-25 00:07:21,467 fail2ban.action         [1]: DEBUG   iptables -w -n -L INPUT | grep -q 'f2b-sshd[ \t]'
2018-04-25 00:07:21,483 fail2ban.utils          [1]: DEBUG   7f6c74bd2ce8 -- returned successfully 0
2018-04-25 00:07:21,485 fail2ban.action         [1]: DEBUG   iptables -w -I f2b-sshd 1 -s 198.51.100.0 -j REJECT --reject-with icmp-port-unreachable
2018-04-25 00:07:21,511 fail2ban.utils          [1]: DEBUG   7f6c7591d4b0 -- returned successfully 0
2018-04-25 00:07:21,512 fail2ban.actions        [1]: DEBUG   Banned 1 / 1, 1 ticket(s) in 'sshd'
```

### Use fail2ban-client

[Fail2ban commands][3] can be used through the container. Here is an example if 
you want to ban an IP manually:

```bash
docker exec -it <CONTAINER> fail2ban-client set <JAIL> banip <IP>
```

### Custom actions and filters

Custom actions and filters can be added in `/data/action.d` and 
`/data/filter.d`. If you add an action or filter that already exists, it will 
be overridden while printing out a warning about it. 

> :warning: Container has to be restarted to propagate changes


### Available Environment variables

* `TZ` : The timezone assigned to the container (default: `UTC`)
* `F2B_LOG_LEVEL` : Log level output (default: `INFO`)
* `F2B_DB_PURGE_AGE` : Age at which bans should be purged from the database (default: `1d`)
* `F2B_MAX_RETRY` : Number of failures before a host get banned (default: `5`)
* `F2B_DEST_EMAIL` : Destination email address used solely for the interpolations in configuration files (default: `root@localhost`)
* `F2B_SENDER` : Sender email address used solely for some actions (default: `root@$(hostname -f)`)
* `F2B_ACTION` : Default action on ban (default: `%(action_mwl)s`)
* `SSMTP_HOST` : SMTP server host
* `SSMTP_PORT` : SMTP server port (default: `25`)
* `SSMTP_HOSTNAME` : Full hostname (default: `$(hostname -f)`)
* `SSMTP_USER` : SMTP username
* `SSMTP_PASSWORD` : SMTP password
* `SSMTP_TLS` : SSL/TLS (default: `NO`)

### Volumes

* `/data` : Contains customs jails, actions and filters and Fail2ban persistent database


# Changelog

### 0.10.4-RC3 (2018/10/06)

* Add whois (Issue #6)

### 0.10.4-RC2 (2018/10/05)

* Allow to add custom actions and filters through `/data/action.d` and `/data/filter.d` folders (Issue #4)
* Relocate database to `/data/db` and jails to `/data/jail.d` (breaking change, see README.md)

### 0.10.4-RC1 (2018/10/04)

* Upgrade to Fail2ban 0.10.4

### 0.10.3.1-RC4 (2018/08/19)

* Add curl (Issue #1)

### 0.10.3.1-RC3 (2018/07/28)

* Upgrade based image to Alpine Linux 3.8
* Unset sensitive vars

### 0.10.3.1-RC2 (2018/05/07)

* Add mail alerts configurations with SSMTP
* Add healthcheck

### 0.10.3.1-RC1 (2018/04/25)

* Initial version based on Fail2ban 0.10.3.1



[1]: https://www.fail2ban.org
[2]: https://hub.docker.com/r/crazymax/
[3]: http://www.fail2ban.org/wiki/index.php/Commands
[4]: https://en.wikipedia.org/wiki/Iptables
