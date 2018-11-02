
# docker-fail2ban

This Alpine based Docker image runs [fail2ban][1] on the
host's network with privileges to edit the [iptables][4]. Create custom 
"filters" and "jails" to block spam and brute-force attacks before they hit your
other containers. 

> :warning: This container require a docker version greater than 17.06 to 
  function without some slight modifications!

# Acknowledgments and Thanks

This repository was forked from `@crazymax` to be able to modify it so that it
works with my setup. If you are interested, [check out his][2] other Docker 
images.

# Usage

## Run with `docker run`

This container thrives the best while in a docker-compose setup, but can also 
launched stand-alone by running the two following commands:
```bash
docker build --tag jonasal/fail2ban:latest .
docker run -d --network host --cap-add NET_ADMIN --cap-add NET_RAW \
  --name fail2ban \
  -v log_collector:/xlogs \
  jonasal/fail2ban:latest
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

## Locating The Logs

As previously stated, this container is designed to live in a docker-compose 
environment where many containers are running a single service each. This 
container is the "primary" caretaker of the `log_collector` named volume, which 
should be mounted to any other container you want to obtain logs from. 

#### Here I create a basic example with Nextcloud as the service to protect

Create a new "jail" file called `nextcloud.conf` in `data/jail.d/`:
```
[nextcloud]
backend = auto
enabled = true
filter = ncFilter
logpath = /xlogs/nextcloud.log
```
Here we have also stated a custom filter, called "ncFilter", which 
fail2ban expects to find inside `data/filter.d/`. So the file `ncFilter.conf`
needs to be created and may look like this.
```
[Definition]
failregex=^.*Login failed: '.*' \(Remote IP: '<HOST>'\).*$
```
Inside the container running Nextcloud you need to mount the named volume 
`log_collector`, or whatever name you give it, and make sure the Nextcloud 
service place its logs inside this. This volume is then mounted at `/xlogs` in
the fail2ban container, which is where we direct it by defining 
`logpath = /xlogs/nextcloud.log` inside the jail file. This way multiple 
services' logs can be observed from a single fail2ban container. 

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

## Good to Know

### Use the fail2ban-client

[Fail2ban commands][3] can be used through the container. Here is an example if 
you want to ban an IP manually:

```bash
docker exec -it <CONTAINER> fail2ban-client set <JAIL> banip <IP>
```

### Custom actions and filters

Custom actions and filters can be added in `/data/action.d` and 
`/data/filter.d`. If you add an action or filter that already exists, it will 
be overridden while printing out a warning about it. 

### Available Environment variables

* `TZ` : The timezone assigned to the container (default: `UTC`)
* `F2B_LOG_LEVEL` : Log level output (default: `INFO`)
* `F2B_DB_PURGE_AGE` : Age at which bans should be purged from the database (default: `1d`)
* `F2B_MAX_RETRY` : Number of failures before a host get banned (default: `5`)
* `F2B_DEST_EMAIL` : Destination email address used solely for the interpolations in configuration files (default: `root@localhost`)
* `F2B_SENDER` : Sender email address used solely for some actions (default: `root@fail2ban`)
* `F2B_ACTION` : Default action on ban (default: `%(action_mw)s`)
* `SSMTP_HOST` : SMTP server host
* `SSMTP_PORT` : SMTP server port (default: `25`)
* `SSMTP_HOSTNAME` : Full hostname (default: `fail2ban`)
* `SSMTP_USER` : SMTP username
* `SSMTP_PASSWORD` : SMTP password
* `SSMTP_TLS` : SSL/TLS (default: `YES`)

### Volumes

* `/fail2ban_db` : Contains fail2ban's persistent database


# Extensive Details

If you are really interested in how this container works I welcome you into this
section. However, I try to write down as many details I can to be able to come
back to this code in a couple of years time and understand why I did what I did.
So it might be a bit rambly at some places.

## Iptables and Chains

Iptables are, as the name suggests, tables of rules deciding how internet data
packets shall be routed inside the computer. In these tables there are, by 
default, five chains:
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
connection to port 22, which is SSH, in which case you may add a DROP rule from 
all IP addresses going to port 22 inside the `INPUT` chain. However, you also 
want to be able to connect to another computer, from your current one, over SSH 
so therefore you allow any IP going to port 22 in the `OUTPUT` chain. 
This way you may split up rules in an easy way so they do not conflict with 
each other. Finally some `POSTROUTING` is made before the packets are sent on
their way again.

## Docker 17.06 and Chains

As mentioned above, the `PREROUTING` chain is allowed to divide the incoming 
traffic into three different "sub-chains" depending on what classification it 
sets on the data packet. In a similar manner you can actually split traffic 
inside these "sub-chains" into further "sub-sub-chains" for even finer control 
of what should happen to the packets. This is actually what the Docker service 
does, by attaching a `DOCKER` chain onto the `FORWARD` chain. If you have the 
Docker service running you should be able to see these chains if you run the 
following command on your host.
```bash 
sudo iptables -L
```

In this chain any rule set by the docker service would end up. What is good
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

fail2ban use chains to easily divide different rules for different services. 
This way you may have a specific IP banned for one web service while it is 
allowed to access another. Nevertheless, what is important to know is that 
these chains are, by default, attached to the `INPUT` chain of the host. This
is desired if the services you are trying to protect are running on the host as
the packets will be directed to `INPUT` by the `PREROUTING`. However, when you 
are running your services inside containers they will reside inside the Docker 
network. As mentioned above, packets destined for the Docker network gets routed
through the `FORWARD` chain by `PREROUTING`, and the fail2ban rules present in 
`INPUT` will be completely bypassed.

To remedy this I make fail2ban attach its chains to the `DOCKER-USER` chain 
instead of `INPUT`, as that chain is specifically allocated for user defined
rules that are meant to be applied to the containers. This is done by simply 
stating the chain name in the `data/action.d/iptables-common.local` file which
will overwrite the default in the main `iptables-common.conf` file. 

Unfortunately this means that any packets coming in to the `INPUT` chain will 
bypass these rules that now reside under the `FORWARD` chain. If you have 
services running on your host computer's native network you could just spin
up another container of fail2ban and just remove the `iptables-common.local` 
file outright to restore "normal" functionality. For even more advanced method 
continue reading below. 

## Custom Chains

In this application I use chains I know exist and in what order they come. 
However, as stated above, the problem exist where fail2ban only affects either
the host's network by applying rules to `INPUT`, or only to the Docker network
by applying them to `DOCKER-USER`. There is a guy who seems to create a 
`FILTER` chain that resides right after `PREROUTING`, and this chain will then 
split the traffic into `INPUT` or `FORWARD`. This way rules applied to `FILTER` 
will affect both, but is more work required by the user. You may have a 
[look at it][8] if you want to, just change the chain name inside 
`data/action.d/iptables-common.local` afterwards.


# Changelog

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
