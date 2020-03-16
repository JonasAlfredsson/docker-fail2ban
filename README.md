# docker-fail2ban

This Alpine based Docker image runs [fail2ban][1] on the host's network with
privileges to edit the [iptables][4]. Create custom "filters" and "jails" to
block spam and brute-force attacks before they hit your other containers.

> :information_source: This has been configured to block the spam from reaching
  containers that are using the normal **Docker network**, and not the **host**
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

- Check out the [Jails, Filters, Actions & Logs](#jails-filters-actions-and-logs)
  section to understand how to create ban rules.
- The [Good to Know](#good-to-know) section will highlight some behavior that
  you probably want to know about before starting.
- The [Extensive Details](#extensive-details) section is long and rambly and
  used by me to remember all the intricate details that were necessary to
  figure out while designing this. Feel free to read if you want.
- The [Changelog](#changelog) is at the bottom.


## Available Environment Variables
- `TZ`: The [timezone][13] assigned to the container (default: `Etc/UTC`)
- `IPTABLES_CHAIN`: The [iptables CHAIN](#fail2ban-and-chains) used for
                    attaching banned IP addresses to (default: `DOCKER-USER`)
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



# Jails, Filters, Actions and Logs

`fail2ban` issues bans by scanning through [log files](#logs) to find a regex
pattern (see [filters](#filters)) which indicates that some IP has performed,
for example, a failed login attempt. If these failed attempts continue it may
be because of a brute-force attack, and `fail2ban` will then perform the
defined "[`banaction`](#actions)" to stop this. The default action is that
`fail2ban` will store the offending IP in its database before adding a rule to
the `iptables` which block any further communication with that peer.

So for this service to be useful you will first need another service that
produce a log file that `fail2ban` can monitor for suspicious behavior. In the
rest of this section I will use a basic example with [Nextcloud][12] as the
service to protect, and it will output any login attempts to the file
`nextcloud.log`. How this log is made readable from another container is
explained further in the [Logs](#logs) section, but for now we will just say
that it is located at `/xlogs/nextcloud.log` in the `fail2ban` container.

## Custom Jails, Actions and Filters
Any custom jails, actions or filters, that are created by the user, should be
mounted/copied into the container under the following folder locations:

- `/data/jail.d/`
- `/data/action.d/`
- `/data/filter.d/`

Files found in these folders will then be symlinked over to the corresponding
fail2ban folders under `/etc/fail2ban/<...>` at startup of this container. If
you add a custom file that has the exact same name as a file which exist at
one of those locations, the destination file will be overwritten by the custom
one while a message is printed in the log notifying you about it.

### Jails
Jail files allows you to tailor the ban settings for each individual service
being monitored. Create a new `jail` file called `nextcloud.conf` in
`/data/jail.d/`:

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
to find this filter inside `/etc/fail2ban/filter.d/`, so if this is not a
"default" filter the file `ncFilter.conf` needs to be created and copied into
the [`/data/filter.d/`](#jails-filters-actions-and-logs) folder.

A usable filter for the Nextcloud service might look something like this:

```
[Definition]
failregex=^.*Login failed: '.*' \(Remote IP: '<HOST>'\).*$
```

This regex will then trigger on any line that looks like this:

```
2019-05-18T14:44:45Z Random text. Login failed: 'whatever' (Remote IP: '192.168.0.1') More text
```

Here the `<HOST>` parameter is the most important thing, as this is the IP
which will be added to the `iptables` when a ban is handed out.

Check out [Log File Layout](#log-file-layout) section for additional notes
about some interesting limitations imposed on log file's format, and the
[official manual][14] for more info about the regex options.

### Actions
The default action taken, when `fail2ban` identifies an IP that need to be
banned, is defined in the file `/etc/fail2ban/jail.conf` on the following line:

```
banaction = iptables-multiport
```

This means that it is the instructions that are found in the file
`/etc/fail2ban/action.d/iptables-multiport.conf` that will be followed in order
to properly add the correct rules to the `iptables`.

This can be changed for each individual jail, but this will most likely be
better to define on a more "global" scale in the main `jail.conf` file. However,
unless you are running some alternative firewall program (like `firewalld`,
`shorewall` or [`nftables`](#nftables)) you will not need to edit this.

> NOTE: The environment variable `F2B_ACTION` allows you define what "action"
        the [mail program](#notification-mails) will make when you need to be
        notified about something. This is not directly related to "banaction",
        so the naming is a bit unfortunate.



## Logs
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
enables the `jails` again and reloads `fail2ban` when the missing log files
shows up.


## Notification Mails
`fail2ban` can send mail through the `sendmail` program. By default it sends a
mail every time the server starts, a jail starts and a ban is issued. This got
a bit annoying so anything else than mails regarding bans issued is
[shut off][9] by setting two variables inside `action.d/sendmail-common.local`
to empty strings. The default behavior can be reinstated by just removing this
file.

If no external mail provider is specified (check out the `fail2ban.env` file
for an example with Gmail), all mail will be directed to `root@localhost:25`.
This way you should be able to read any mails by simply typing `mail` (or
`sudo mail`) in you host machine's terminal.

The content of these mails are regulated by the string that is assigned to the
environment variable `F2B_ACTION`. If you are using the "sendmail" program there
is currently four different options available for you, and they point to
specific files that should be run when sending mail. The options are:

- `action_`: action.d/[**sendmail**.conf][19]
- `action_mw`: action.d/[**sendmail-whois**.conf][20]
- `action_mwl`: action.d/[**sendmail-whois-lines**.conf][21]
- ` `: _Don't send any mails_

If you enter a blank line no mails will be sent, and the contents of the other
ones can be observed by following the links.



# Extensive Details

If you are really interested in how this container works I welcome you into this
section. However, I try to write down as many details I can, in order to be able
to come back to this code in a couple of years time and understand why I did
what I did. So it might be a bit rambly at some places.


## Iptables and Chains
Iptables are, as the name suggests, tables of rules deciding how internet data
packets shall be routed inside the computer. In these tables there are, by
default, five **CHAINS**:

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

Nevertheless, what is important to know is that these fail2ban chains are, by
default, attached to the `INPUT` chain of the host. This is desired if the
services you are trying to protect are running directly on the host, since those
packets will be directed to the `INPUT` chain by the `PREROUTING` rules.
However, when you are running your services inside Docker containers they will
usually reside inside the **Docker network** (unless you specify them to use
the **host** network). As mentioned [above](#docker--17.06-and-chains), packets
destined for the Docker network instead gets routed through the `FORWARD` chain
by `PREROUTING`, and the fail2ban rules present in `INPUT` will be completely
bypassed if nothing is done to combat this.

To remedy this I configure fail2ban to attach its chains to the `DOCKER-USER`
chain instead of `INPUT`, by default, as that chain is specifically created for
user defined rules that are meant to be applied to the containers located in
the Docker network. In the startup script this is done by editing a single line
in the file `/etc/fail2ban/action.d/iptables-common.conf` to instead use the
value from the environment variable `IPTABLES_CHAIN` mentioned in the
[beginning](#available-environment-variables) of this README.

Unfortunately this means that any packets now coming in to the `INPUT` chain
will bypass these rules that now reside under the `FORWARD` chain. If you have
services running on your **host's network** you could just spin up an additional
container of fail2ban and set `IPTABLES_CHAIN=INPUT` for that one.

For an even more advanced method, where you would only need one container to
block traffic for both `INPUT` and `FORWARD`, continue reading the next section
[below](#custom-chains).


## Custom Chains
When I designed this container I only use chains I know will exist on all
computers, so other people can use this without too much tinkering. However, as
stated in the section [above](#fail2ban-and-chains), the problem remain where
fail2ban only affects either the **host's network**, by applying rules to
`INPUT`, or only the **Docker network** by applying them to `DOCKER-USER`.

However, in my research I stumbled upon a guide that seems to create a
completely new `FILTER` chain that resides right after `PREROUTING`, but at the
same time before the other chains. This new chain then becomes responsible for
the task of splitting the traffic into `INPUT` or `FORWARD`, which means that
any rules applied to `FILTER` will affect both of these following chains.

This sounds nice, but there is some extra manual labor required by the user to
make this work as intended. You may have a [look at the guide][8] if you want
to experiment with this, just remember change chain name in the
`IPTABLES_CHAIN` variable afterwards.


## Older Docker Versions
If you have an older version of Docker, and you desperately need this to work
without upgrading, you may just change the `IPTABLES_CHAIN=DOCKER-USER`
environment variable to `IPTABLES_CHAIN=FORWARD` instead.

This should make all the fail2ban rules come before any Docker rules and the
effect [should be the same][10] as having them in the `DOCKER-USER` chain.
However, remember that these bans now apply to **ALL** forwarded traffic.
Usually this will not cause any problems, in a home server, but might be
problematic in other cases.


## `nftables`
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

### 0.10.4.3-Beta2 (2020-03-15)

* Add check to make sure all referenced `filter`s are present at startup.
* Rewrite the `config_watcher` function, to utilize the shared mutex better.
* Add the `--optimize=2` flag when installing Fail2ban.
* Make clarifications to previous entries in the changelog.

### 0.10.4.3-Beta1 (2020-03-13)

* Move over fully to Python 3.
* Include `pyinotify` backend to allow being notified about logfile changes
  instead of polling.
* Include `dnspython3` pip package to allow fail2ban to print more info about
  the banned IPs.
* Fix HEALTCHECK command.

### 0.10.4.2-Beta2 (2020-03-13)

* Make so that `jails`, `actions` and `filers` are instead symlinked in from
  `/data/...`
* Fix the `auto_enable_jail` functionality for multiple files and make so it
  handles symlinks.
* Reduce the number of build steps in the Dockerfile.
* Add information about incompatibility with `nftables`.
* Make better comments in the code.

### 0.10.4.2-Beta1 (2019-05-19)

* Refactor basically all the code.
* Create the `auto_enable_jail` functionality.
* Include colored output.
* More input parameters.
* A ton more documentation.

### 0.10.4.1-Beta2 (2018-11-02)

* Remove `wget`.
* Update the documentation.
* This container is now available on Docker Hub under `jonasal/fail2ban`.
* Include a Makefile with some nice commands.

### 0.10.4.1-Beta1 (2018-11-02)

* `@JonasAlfredsson` forks the repository.
* Make fail2ban attach to the `DOCKER-USER` chain in the iptables.
* Make the mailing functionality send to the right location.
* Refactor the entrypoint.sh script.
* Refactor the Dockerfile.
* Remove unused files and refactor folder structure.
* Much more documentation.

### 0.10.4-RC3 (2018-10-06)

* Add whois (Issue #6).

### 0.10.4-RC2 (2018-10-05)

* Allow to add custom actions and filters through `/data/action.d` and
  `/data/filter.d` folders (Issue #4).
* Relocate database to `/data/db` and jails to `/data/jail.d` (breaking change,
  see README.md).

### 0.10.4-RC1 (2018-10-04)

* Upgrade to Fail2ban 0.10.4

### 0.10.3.1-RC4 (2018-08-19)

* Add curl (Issue #1).

### 0.10.3.1-RC3 (2018-07-28)

* Upgrade based image to Alpine Linux 3.8.
* Unset sensitive vars.

### 0.10.3.1-RC2 (2018-05-07)

* Add mail alerts configurations with SSMTP.
* Add HEALTHCHECK command.

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
[19]: https://github.com/fail2ban/fail2ban/blob/master/config/action.d/sendmail.conf
[20]: https://github.com/fail2ban/fail2ban/blob/master/config/action.d/sendmail-whois.conf
[21]: https://github.com/fail2ban/fail2ban/blob/master/config/action.d/sendmail-whois-lines.conf
