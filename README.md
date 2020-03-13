# docker-fail2ban

This Alpine based Docker image runs [fail2ban][1] on the host's network with
privileges to edit the [iptables][4]. Create custom "filters" and "jails" to
block spam and brute-force attacks before they hit your other containers.

> :information_source: This has been modified to block the spam from reaching
containers that are using the normal **Docker network**, and not the **`host`**
network. See full explanation under [Extensive Details](#extensive-details).

> :warning: This container require a docker version greater than 17.06 to
  function without some [slight modifications][11]!

> :warning: There is currently some compatibility issues with the new
  `nftables` and this container. Check out how to revert back to the old
  `iptables` [here](#nftables).



# Acknowledgements and Thanks

This repository was forked from `@crazymax` to be able to modify it so that it
works with my setup, and to add some additional functionality. If you are
interested, [check out his][2] other Docker images.



# Usage

- Check out the [Jails, Filters & Logs](#jails-filters-and-logs) section to
  understand how to create ban rules.
- The [Good to Know](#good-to-know) section will highlight some behavior that
  you probably want to know about before starting.
- The [Extensive Details](#extensive-details) section is long and rambly and
  used by me to remember all the intricate details that were necessary to
  figure out while designing this. Feel free to read if you want.
- The [Changelog](#changelog) is at the bottom.


## Available Environment Variables
- `TZ`: The [timezone][13] assigned to the container (default: `UTC`)
- `F2B_LOG_LEVEL`: Log level output (default: `INFO`)
- `F2B_BAN_TIME`: How long a ban should last (default: `600` [i.e. 10 minutes])
- `F2B_FIND_TIME`: Window of time to determine repeat offenders
                   (default: `600` [i.e. 10 minutes])
- `F2B_MAX_RETRY`: Number of failures before a host gets banned (default: `5`)
- `F2B_DB_PURGE_AGE`: Age at which old bans should be purged from the database
                      (default: `86400` [i.e. 24h])
- `F2B_DEST_EMAIL`: Destination address to send
                    [notification e-mails](#notification-mails) to
                    (default: `root@localhost`)
- `F2B_SENDER`: Sender email address used by some actions
                (default: `root@fail2ban`)
- `F2B_ACTION`: Default action on ban (default: `%(action_mw)s`)
- `SSMTP_HOST`: SMTP server host
- `SSMTP_PORT`: SMTP server port (default: `25`)
- `SSMTP_HOSTNAME`: Full hostname (default: `fail2ban`)
- `SSMTP_USER`: SMTP username
- `SSMTP_PASSWORD`: SMTP password
- `SSMTP_TLS`: SSL/TLS (default: `YES`)


## Volumes
- `/fail2ban_db` : Contains fail2ban's database of previous bans


## Run with `docker run`
When launching this container as a stand-alone instance, I would probably use
host mounted folders to make data persistent and shared between services. The
following two commands will facilitate that:

```bash
docker build --tag fail2banService .
docker run -d --network host --cap-add NET_ADMIN --cap-add NET_RAW \
           -v $(pwd)/persistent/logs:/xlogs
           -v $(pwd)/persistent/db:/fail2ban_db
           --name fail2ban fail2banService
```


## Run with `docker-compose`
Docker-Compose is my preferred way to run this image. See the example of a
compose file inside the `examples/` folder, and you may use the `.env` file to
define all the variables in a separate location. Then it can all be launched
via the following commands:

```bash
docker-compose build --pull
docker-compose up
```



# Jails, Filters and Logs

`fail2ban` issues bans by scanning through [log files](#logs) to find a regex
pattern (see [filters](#filters)) which indicates that some IP has performed,
for example, a failed login attempt. If these failed attempts continues it may
be because of a brute-force attack, and `fail2ban` will then add this IP to a
`jail` and then add a rule to the `iptables` which block any further
communication with that peer.

So first of all you need another service that produce a log file that `fail2ban`
can monitor for suspicious behavior. Here I will create a basic example with
[Nextcloud][12] as the service to protect, and it will output any login attempts
to the file `nextcloud.log`. How this log is made readable from another
container is explained further in the [Logs](#logs) section. For now we will
just say that it is located at `/xlogs/nextcloud.log` in the `fail2ban`
container.

### Jails
Jail files allows you to tailor the ban settings for each individual service
being monitored. Create a new `jail` file called `nextcloud.conf` in
`data/jail.d/`:

```
[nextcloud]
enabled = true
filter = ncFilter
logpath = /xlogs/nextcloud.log
```

These are the minimal amount of settings that are needed to be defined, and
anything else will use the [default values][17].

> NOTE: The default values may also be changed via the environment variables
        `F2B_BAN_TIME`, `F2B_FIND_TIME` and `F2B_MAX_RETRY`.


### Filters
In the config file above we defined that this jail should use a custom filter,
called `ncFilter`, when monitoring the Nextcloud log file. This "filter" is
another file which will contain the regex(s) used to identify what lines in the
log file that should be identified as failed login attempts. `fail2ban` expects
to find this filter  inside `data/filter.d/`, so the file `ncFilter.conf` needs
to be created and may look like this:

```
[Definition]
failregex=^.*Login failed: '.*' \(Remote IP: '<HOST>'\).*$
```

This will then trigger on any line that looks something like this:

```
2019-05-18T14:44:45Z Random text. Login failed: 'whatever' (Remote IP: '192.168.0.1')
```

Check out [Log File Layout](#log-file-layout) section for additional notes
about  some interesting limitations imposed on log file's format, and the
[official manual][14] for more info about the regex options.

### Logs
Up till now we have assumed that the `fail2ban` container had easy access to the
log files of interest. However, in an environment with many other containers,
that are running a single service each, we must design a method that can be used
by all of these to share their logs.

The most simple and straight forward method is to use a host mounted folder,
where you later configure all external services to place their log files.
However, it is also possible to use a `named volume`, which might be preferred
when using `docker-compose`.

Inside the container running Nextcloud you need to mount the named volume
`log_collector`, or whatever name you give it, and make sure the Nextcloud
service place its logs inside this. This volume is then mounted at `/xlogs` in
the fail2ban container, which is where it expects to find the log file as
we have defined `logpath = /xlogs/nextcloud.log` inside the jail config file.
This way multiple services' logs can be observed from a single fail2ban
container. The only issue is that this requires the folder/volume to be
writable by all of the monitored services, which often means that you have to
set the `777` permission on this folder.

A `docker-compose` file for this may look something like this.
```yaml
.
.
.
  nextcloud:
    build: ./nextcloud
    restart: unless-stopped
    volumes:
      - nextcloud_www:/var/www/html
      - nextcloud_data:/var/nc_data
      - log_collector:/log/path
    depends_on:
      - fail2ban

  fail2ban:
    build: ./fail2ban
    restart: unless-stopped
    network_mode: "host"
    cap_add:
      - NET_ADMIN
      - NET_RAW
    volumes:
      - log_collector:/xlogs

volumes:
  nextcloud_data:
  nextcloud_www:
  log_collector:
```



# Good to Know

## Use the fail2ban-client
[Fail2ban commands][3] can be given to the container directly if so desired.
Here is an example if you want to ban an IP manually:

```bash
docker exec <CONTAINER> fail2ban-client set <JAIL> banip <IP>
```

If you want to manually un-ban someone this can be executed:

```bash
docker exec <CONTAINER> fail2ban-client set <JAIL> unbanip <IP>
```


## Custom Actions and Filters
Custom actions and filters can be added in `/data/action.d` and
`/data/filter.d`. If you add an action or filter that already exists, it will
be overridden while printing out a warning about it.


## Log File Layout
The [documentation][14] states that the log files that are parsed needs to have
a timestamp in the beginning of the line. This is a built in functionality of
`fail2ban`, and **cannot** be changed. If a regex is created with a `^`, i.e.
"at the beginning of the line", then the anchor actually refers to the start of
the **remainder** of the line, _after_ the preceding timestamp and intervening
whitespace.

If `fail2ban` is unable to interpret the timestamp in the beginning it will tell
you so in its output, and then you have two options:
- Reconfigure your daemon to log with a timestamp in a more common format.
- File a [bug report][18] to `fail2ban` asking to have your timestamp format
  included.

However, since this functionality is still undocumented for the users, trial and
error has shown it is [not always necessary][15] for the timestamp to be at the
beginning of the line, if you allow for some wildcard expansion in the regex.
For example: in the Nginx log format it will be able to find the timestamp if
it looks something like this:

```
1.2.3.4 - - [19/May/2019:08:52:51 +0000] "GET / HTTP/1.1" 200 1100 ....
```

With the following filter:


```
failregex = ^<HOST> -.*
```


## Missing Log Files
If a log file is defined in a `jail`, but the service that produce this file
has not started yet, `fail2ban` will crash since it lacks error handling in
the case where files are missing. I have therefore created the functionality
where the startup script will monitor the file paths of the logs defined in
every `jail` config, and disable them until the target file shows up. This then
enables the `jails` again and reloads `fail2ban` when the missing files exists
again.


## Notification Mails
`fail2ban` can send mail through the `sendmail` program. By default it sends a
mail every time the server starts, a jail starts and a ban is issued. This got
a bit annoying so anything else than mails regarding bans issued is
[shut off][9] by setting two variables inside `action.d/sendmail-common.local`
to empty strings. The default behavior can be reinstated by just removing this
file.

If no external mail provider is specified (check out the `fail2ban.env` file
for an example with gmail), all mail will be directed to `root@localhost:25`.
This way you should be able to read any mails by simply typing `mail` (or
`sudo mail`) in you host machine's terminal.



# Extensive Details

If you are really interested in how this container works I welcome you into this
section. However, I try to write down as many details I can, in order to be able
to come back to this code in a couple of years time and understand why I did
what I did. So it might be a bit rambly at some places.


## Iptables and Chains
Iptables are, as the name suggests, tables of rules deciding how internet data
packets shall be routed inside the computer. In these tables there are, by
default, five _chains_:

- `PREROUTING`
- `INPUT`
- `FORWARD`
- `OUTPUT`
- `POSTROUTING`

I really like [this post][6], about how a packet is routed around inside these
chains, but to summarize you may say that first `PREROUTING` decides if the
incoming packet should be handed over to either `INPUT`, `FORWARD` or `OUTPUT`.
Inside these three chains you usually apply rules that only affect the packets
who have to go through them. For example you may want to block all incoming
connections to port 22, which is SSH, in which case you may add a DROP rule from
all IP addresses going to port 22 inside the `INPUT` chain. However, you also
want to be able to connect to another computer, from your current one, over SSH
so therefore you allow any IP going to port 22 in the `OUTPUT` chain.
This way you may split up rules in an easy way so they do not conflict with
each other. Finally some `POSTROUTING` is made before the packets are sent on
their way again.


## Docker ≥ 17.06 and Chains
As mentioned above, the `PREROUTING` chain is allowed to divide the incoming
traffic into three different "sub-chains" depending on what classification it
sets on the data packet. In a similar manner you can actually split traffic
inside these "sub-chains" into further "sub-sub-chains" for even finer control
of what should happen to the packets.

This is actually what the Docker service does, by attaching a `DOCKER`
chain onto the `FORWARD` chain. If you have the Docker service running you
should be able to see these chains if you run the following command on your
host.

```bash
sudo iptables -nL
```

More detailed information can also be obtained trough following command:

```bash
sudo iptables -t nat -nL --line-numbers
```

In this chain any rule set by the Docker service would end up. What is good
with this is that packets would only end up here if they were destined for a
Docker container in the first place. This way the rules set here could be easily
formulated without affecting the rest of the host system's internet connection.

However, as this chain is modified automatically by the Docker service, you
would not have much luck setting custom rules you wanted to be persistent there.
Luckily, in a [pull request][5] leading up to the 17.06 release of Docker, there
were new features added to the iptables that are created by the Docker service.
It introduced a new chain called `DOCKER-USER` which will be placed before the
normal `DOCKER` chain. This is empty by default and will not be touched by
Docker at all, as it is [intended][7] to be used for custom user defined rules.


## fail2ban and Chains
`fail2ban` creates one unique chain for every `jail`/service defined, in order
to easily divide different rules for different services. This way you may have a
specific IP banned for one web service while it is allowed to access another.

Nevertheless, what is important to know is that these chains are, by default,
attached to the `INPUT` chain of the host. This is desired if the services you
are trying to protect are running on the host, as the packets will be directed
to `INPUT` by the `PREROUTING`. However, when you are running your services
inside containers they will reside inside the **Docker network**. As mentioned
[above](#docker-≥-17.06-and-chains), packets destined for the Docker network
gets routed through the `FORWARD` chain by `PREROUTING`, and the fail2ban rules
present in `INPUT` will be completely bypassed.

To remedy this I configure fail2ban to attach its chains to the `DOCKER-USER`
chain instead of `INPUT`, as that chain is specifically allocated for user
defined rules that are meant to be applied to the containers. This is done by
simply adding that chain name to the `data/action.d/iptables-common.local` file,
which will overwrite the default in the main `iptables-common.conf` file.

Unfortunately this means that any packets coming in to the `INPUT` chain will
bypass these rules that now reside under the `FORWARD` chain. If you have
services running on your host computer's native network you could just spin
up another container of fail2ban and just remove the `iptables-common.local`
file outright to restore "normal" functionality. For even more advanced method
continue reading [below](#custom-chains).


## Custom Chains
In this application I use chains I know exist, and in what order they come.
However, as stated [above](#fail2ban-and-chains), the problem remain where
fail2ban only affects either the host's network, by applying rules to `INPUT`,
or only to the Docker network by applying them to `DOCKER-USER`. In my research
I stumbled upon a guide that seems to create a `FILTER` chain that resides right
after `PREROUTING`, and this chain will then split the traffic into `INPUT` or
`FORWARD`. This way rules applied to `FILTER` will affect both, but is more work
required by the user. You may have a [look at it][8] if you want to, just change
the chain name inside `data/action.d/iptables-common.local` afterwards.


## Older Docker Versions
If you have an older version of Docker, and you desperately need this to work
without upgrading, you may just change the line reading `DOCKER-USER` to
`FORWARD` inside the `data/action.d/iptables-common.local` file. This should
make all the fail2ban rules come before any Docker rules and the effect
[should be the same][10]  as having them in the `DOCKER-USER` chain. However,
remember that these bans now apply to **ALL** forwarded traffic. Usually this
will not cause any problems, in a home server, but might be problematic in
other cases.


## nftables
I have not yet had time to go into detail on how to use the new `nftables`
with fail2ban inside Docker, so for now I have just reverted to use the old
legacy `iptables`. I used this guide for [Debian Buster][16], where you have
to run the following commands as root:

```
update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
update-alternatives --set arptables /usr/sbin/arptables-legacy
update-alternatives --set ebtables /usr/sbin/ebtables-legacy
```

After this it is necessary to reboot so that all services start using the
legacy settings again. This solved the problem where fail2ban would output
the following error messages:

```
stderr: 'iptables: No chain/target/match by that name.'
returned 1
```



# Changelog

### 0.10.4.3-Beta1 (2020-03-13)

* Move over fully to Python 3
* Include `pyinotify` backend
* Fix HEALTCHECK command

### 0.10.4.2-Beta2 (2020-03-13)

* Make so that `jails`, `actions` and `filers` are symlinked in from `/data/...`
* Fix the `auto_enable_jail` functionality for multiple files and make so it
  handles symlinks.
* Make better comments in the code.

### 0.10.4.2-Beta1 (2019-05-19)

* Refactor all the code.
* Create the `auto_enable_jail` functionality.
* Include coloured output.
* More input parameters.
* A ton more documentation.

### 0.10.4.1-Beta2 (2018-11-02)

* Remove wget
* Update the documentation
* This container is now available at Docker Hub under `jonasal/fail2ban`
* Include Makefile

### 0.10.4.1-Beta1 (2018-11-02)

* `@JonasAlfredsson` forks the repository.
* Make fail2ban attach to the `DOCKER-USER` chain in the iptables.
* Make the mailing functionality send to the right location.
* Refactor the entrypoint script.
* Refactor the Dockerfile.
* Remove unused files and refactor folder structure.
* Much more documentation.

### 0.10.4-RC3 (2018-10-06)

* Add whois (Issue #6)

### 0.10.4-RC2 (2018-10-05)

* Allow to add custom actions and filters through `/data/action.d` and `/data/filter.d` folders (Issue #4)
* Relocate database to `/data/db` and jails to `/data/jail.d` (breaking change, see README.md)

### 0.10.4-RC1 (2018-10-04)

* Upgrade to Fail2ban 0.10.4

### 0.10.3.1-RC4 (2018-08-19)

* Add curl (Issue #1)

### 0.10.3.1-RC3 (2018-07-28)

* Upgrade based image to Alpine Linux 3.8
* Unset sensitive vars

### 0.10.3.1-RC2 (2018-05-07)

* Add mail alerts configurations with SSMTP
* Add healthcheck

### 0.10.3.1-RC1 (2018-04-25)

* Initial version based on Fail2ban 0.10.3.1






[1]: https://www.fail2ban.org
[2]: https://hub.docker.com/r/crazymax/
[3]: http://www.fail2ban.org/wiki/index.php/Commands
[4]: https://en.wikipedia.org/wiki/Iptables
[5]: https://github.com/docker/libnetwork/pull/1675
[6]: https://askubuntu.com/a/579242
[7]: https://docs.docker.com/network/iptables/
[8]: https://unrouted.io/2017/08/15/docker-firewall/
[9]: https://serverfault.com/questions/257439/stop-fail2ban-stop-start-notifications
[10]: http://blog.amigapallo.org/2016/04/14/configuring-fail2ban-and-iptables-to-get-along-with-docker/
[11]: https://github.com/JonasAlfredsson/docker-fail2ban#older-docker-versions
[12]: https://nextcloud.com/
[13]: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
[14]: https://www.fail2ban.org/wiki/index.php/MANUAL_0_8#Filters
[15]: https://unix.stackexchange.com/a/345535
[16]: https://wiki.debian.org/nftables
[17]: https://www.fail2ban.org/wiki/index.php/MANUAL_0_8#Jail_Options
[18]: https://github.com/fail2ban/fail2ban/issues
