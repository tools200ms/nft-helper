
# NFT List
Supplements Nftables by domain name based filtering and configuration files.

**NOTE:**
Usage of this tool requires knowledge regarding Linux NFT firewall framework.
For more information check out [NFT Quick reference in 10 minutes](https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes).
Additionally, NFT guides with an examples can be found in [Useful links](#useful-links) section at the bottom of this page.

## Table of contents

- [Overview](#overview)
- [Quick introduction](#quick-introduction)
- [Project's scope](#projects-scope)
- [HowTo Use](#howto-use)
  - [Part I: Interaction](#part-i-interaction)
    - [NFT sets](#nft-sets)
    - [NFT Structure](#nft-structure)
  - [Part II: Installation and Configuration](#part-ii-installation-and-interaction)
    - [Installation](#installation)
    - [Configuration files and directories](#configuration-files-and-directories)
      - [File format](#file-format)
    - [Directives](#directives)
    - [Command line](#command-line)
    - [Periodic runs](#periodic-runs)
    - [White List example](#white-list-example)
  - [Troubleshooting](#troubleshooting)
- [Summary](#summary)
- [Useful links](#useful-links)

## Overview

When managing my network I come across the need to restrict a traffic to a given domain name list.
Sounds easy task, just read the list, resolve names and load IPs to a firewall.
It started with a simple Bash script, once when it has been developed, I got other feature. I could keep domain list in a separated file. 'structure' (firewall configuration) now has been separated from data (domain names).

The firewall is NFT, its `C structure` alike configuration ([look bellow 🠋🠋](#quick-introduction)) that I really like now could be extended by text `one domain per line` format files holding e.g. blacklisted domain names.
My script was reading the list, resolving names and passing this information into proper
place in NFT.

Once there has been means to read domain names, next step seem to be a possibility to load IP addresses, and why not mac addresses?
So the program become capable of loading `network resources`, to indicate where within NFT configuration given
resource set should be added I defined keyword `@set`. A bit later come an idea for an `@include` keyword (for including other files) and `@onpanic` for defining policy in the case of network 'emergency'.

NFT by design provides sophisticated functions such as [timeouts](https://wiki.nftables.org/wiki-nftables/index.php/Element_timeouts), [intervals](https://wiki.nftables.org/wiki-nftables/index.php/Intervals), different data types. Additionally IPs resolved from DNS might change over time. Domain name lists (especially blacklists) do change also, etc. One of the 'musts' for a well-made software is a capability to reload configuration keeping in mind all these sophisticated functions of NFT. Thus, the program requirements has grow comparing original 'read list -> resolve names -> load firewall' concept.

NFT comes with Python bindings, it become clear that to continue Bash must be dropped in favor of Python. But in fact, I keep two versions, Bash `NFT Helper Lite` and Pythons `NFT Helper`.

## Quick introduction
Nftables firewall is configured via `nft` user-space utility, that replaces an old `iptables` but also `ip6tables`, `arptables` and `ebtables` commands. It comes with a new `C structure` alike configuration file format. See simple example bellow:
```
#!/sbin/nft -f

# very simple workstation configuration
flush ruleset

table inet my_table {

    set allowed_hosts {
        type ipv4_addr;
        flags timeout, interval;
    }

    set allowed_ports {
        type inet_service;
        flags interval;
        elements = { ssh, http, https, http-alt, 3000-5000 }
    }

    chain my_input {
        type filter hook input priority 0; policy drop;

        # Input Pert I: set firewall to let for an outgoing connections,
        # while dropping incoming traffic
        iifname lo accept \
            comment "Accept any localhost traffic"
        ct state invalid drop \
            comment "Drop invalid connections"
        ct state { established, related } accept \
            comment "Accept traffic originated from us"

        # Input Part II: do an exception for incoming traffic for
        # `@allowed_hosts` to `allowed_ports`
        tcp dport @allowed_ports \
        ip  saddr @allowed_hosts counter ct state new accept \
            comment "Accept connections for chosen hosts to selected ports"
    }
}
```
This is a very basic firewall configuration. It opens host (`Input Pert I`) for outgoing connections while dropping traffic originated from outside.
But as an exception (`Input Pert II`) chosen `allowed_hosts` hosts can be allowed for connecting host at `allowed_ports`.

Once when NFT with this configuration is loaded (note `flush ruleset` that purges previous settings) `allowed_hosts` is empty.
Therefore no other host is allowed to let in, access can be open with:
```bash
nft add element inet my_table allowed_hosts { 172.22.0.2 }
```
or `NFT Helper` can do this for you. Define file such as:
```
# /etc/nftdef/allowed_hosts.list
# host that are allowed for connecting this box

@allowed_hosts # load bellow addresses into 'allowed_hosts' set
172.22.0.2 # Peer 2
```

and load:
```bash
nft-helper.sh sync /etc/nftdef/allowed_hosts.list
```
`NFT Helper` comes with OpenRC init script to load settings a boot time, and cron script for periodic reloads. More in ...

## Project's scope

The aim of the project is to complement Nftables user-space tools by:
1. providing domain-based filtering
2. letting on keeping data in a separated from NFT configuration files

The key features of `NFT Helper` are:

1. Domain names are resolved by `NFT Helper` using CloudFlare `1.1.1.1` DOH (DNS over HTTP(s)) server. This is actually the most secure way to query domain names.
2. `NFT Helper` handles following network resources:
    * Domain names (example.com) and:
    * IPv4 addresses (10.0.23.3)
    * IPV4 networks (103.31.4.0/22)
    * IPv6 addresses (fe80::e65f:1ff:fe1b:5bee)
    * IPv6 networks (2001:db8:1234::/48)
    * Mac addresses (02:42:ac:16:00:02)

    These data is read from [configuration files](#configuration) and loaded to appropriate [NFT set](#nft-sets).
3. IPs pointed by DNS can change over time, thus `NFT Helper` runs periodic checks to keep firewall coherent with an actual DNS state.

Please note that domain based filtering is not a perfect one. Usually multiple domain names share common IP's. Encrypted connections (that protect privacy) prevent firewall from inspecting network package for source/destination check. Therefore some extra names can 'sneak' under the radar. However this issue is negligible comparing to benefits coming from restricted firewall rule set.

## HowTo Use
`NFT Helper` is interacting with a firewall that is a vital part of a network security.
Therefore this guide is not only touching aspects of `NFT Helper` but primally `Nftables` to present necessary details for user to be aware of what is being done.


### Part I: Interaction
This part explains an interaction of `NFT Helper` with Nftables user-space tools.

#### NFT sets

NFT comes with [NFT sets](https://wiki.nftables.org/wiki-nftables/index.php/Sets) that allow on grouping elements of the same type together.
Example definition of NFT set looks as follows:
```
table inet user_defined_table_name {
       set usedr_defined_set_name {
               type ipv4_addr;
               flags timeout, interval;
               auto-merge;

               elements = { 10.0.0.0/8 }
       }
}
```

Sets can be anonymous, or named. Above example defines named (`usedr_defined_set_name`) set. To have `NFT Helper` to feed sets with a data it must be obviously named.

NFT defines various types of elements, for instance *ipv4_addr* is for keeping IPv4 addresses, *ether_addr* for mac addresses while *ifname* is to group network interfaces (e.g. enp7s0, br0).

`NFT Helper` operates on a Sets of the following types:
* *ipv4_addr* for IPv4,
* *ipv6_addr* for IPv6 elements
* *ether_addr* for mac addresses.

Nftables also provides `typeof` keyword that as documentation states:

> allows you to use a high level expression, then let nftables resolve the base type for you

`NFT Helper` can operate **only** on sets declared with `type`. Trial of loading data into `typeof`, or `type` but of not supported type will fail.

Type of a set elements complemented by flag that specifies more precisely behaviour and format of an elements:
* *timeout* - specifies timeout when a set element is set for expiration, note that various elements within one set can have a different timeouts
* *constant* - set content can not be changed once when it has been bound to a rule
* *interval* - set elements can be intervals, that is IP addresses with network prefixes or address ranges in format: *<first addr>-<last addr>*, e.g.
`192.168.100-192.168.199`

`NFT Helper` validates these flags and acts as follows:
* *timeout* - `NFT Helper` acts as follow:
    1. loads resources to a such set setting up a given or default timeout. Default timeout is `25 h 42 sec.`
    2. does not do `sync` operation, instead it re-loads NFT with a new list resulting in extending expiration time of
       already existing elements, adding new elements, and letting for experiation in Firewall that elements that are
       missing on e new list.
* *constant* - `NFT Helper` acts normally if set is not bound with rule.
* *interval* - `NFT Helper` extends accepted format by network prefixes and address ranges.


`auto-merge` option of `NFT Set` combines a set elements into intervals, this let auto-packing addresses into groups. For instance
adding `10.0.0.0/8` with `11.1.0.0/8` equals to `10.0.0.0/7`. `NFT Helper` handles this option as expected, thus apart of add and
remove, `auto-merge` will additionally result in `merge`, `split` operations.


In NFT there is no type `inet_addr` that would match both types `ipv4_addr` and `ipv6_addr`. Therefore one set can not
hold mixed IPv4 and IPv6 elements. If set has been defined of a `type ipv4_addr` NFT-List will resolve `A` DNS records to acquire IP.
If set is of `type ipv6_addr` `AAAA` DNS records are queried.


#### NFT Structure

If you inspect an example from [Quick introduction](#quick-introduction) there are three noticeable aspects:
- Sets belong to table
- where chains and finally rules are defined
- rules refer to set to apply a certain policy for a given network resources

Sets are a `meeting` point. `NFT helper` fills in Set with a desired IP/mac addresses. NFT helper does not create, modify or delete chains, rules or other 'structural' firewall settings. It only operates within sets, 'NFT helper' can only:
* add, or
* remove **elements** of an indicated NFT sets.

It's administrator's job to define a firewall configuration. NFT Helper is a tool designed for filling and keeping set elements up to date.


### Part II: Installation and Configuration
This part is about how to configure the tool.

#### Installation
`NFT list` is in an early development phase, there is no packages developed yet, you can install it by unpacking
release file into `/` directory:
```bash
tar -xzvf nfthelper-1.2.9-alpha.tar.gz -C /
```
this will simply extract `nftlist.sh` to `/usr/local/bin/` and `nftlist` to `etc/init.d/`.

At this point, only OpenRC is supported (no systemd).

Add nftlist to OpenRC's default runlevel:
```bash
rc-update add nftlist default
```
To launch `NFT List` simply start the service:
```bash
service nftlist start
```
this reads configuration from `/etc/nftlists/available/` and loads NFT sets.
Just after installation as configuration is empty nothing will happen.

#### Configuration files and directories

Refer to your Linux distribution guide to learn how to handle NFT configuration under your system.
Usually (Debian, Alphine) main configuration file is `/etc/nftables.nft` while directory `/etc/nftables.d/` is used to drop in additional settings.

`Nft Helper` uses `/etc/nftlists/` as a storage place for network resources lists.

It holds `available` and `enabled` directories:
```bash
\# tree /etc/nftlists/
/etc/nftlists/
├── available
│   ├── inbound_filter.list
│   └── outbound_filter.list
├── enabled
│   └── outbound_filter.list -> ../available/outbound_filter.list
└── included
    └── phising_list.txt.gz

3 directories, 4 files
```
`NFT Helper` will load files ended with `.list` extension that are located in `/etc/nftlists/enabled/`.

##### File format

The file format expected by `NFT Helper` is a text file holding domain/address list, such as:
```
# /etc/nftlists/avaliable/blacklisted_domain.list

@set inet filter blacklist

bad-domain.xxx.com # don't go there
your-bank.login.space # no comment
# aha ...
specialoffernow.info
```

Comments are marked by `\#` symbol.

### Directives

Resource list should or can be proceeded by an directives:

**\@set family|- \<table name\>|- \<set name\>|-**
Indicates NFT target set for filling in with addresses placed below this instruction.

**\@include \<file name\>**
Include file, file that is to be included must be located inside `/etc/nftlists/included`.
It does not need to have `.list` extension, it can be compressed, the compression algorithm
must be indicated by a correct extension: `.gz`, `.zip` ...


**\@onpanic keep|discard**

This directive defines an action in the case of `panic` signal. If such an event happen, probably
white lists should be discarded from sets while black addresses keeped.
Panic signal can be issued with:
> nftlist panic

command.

## Command line

NFT Sets are updated by `NFT List` each time when revise is started, or reloaded:

```bash
service nftlist start
service nftlist reload
```

`NFT List` can also be called directly from command line:
```bash
# nftlist
Following updates has been found
Id:    action:
 1     add 4 IPv4 elements
        to 'blacklist' set of 'filter' inet table

proceed with update?
      yes    / no / details / help or (y   /n/d/h) - if yes,     update all
  or  yes Ids/ no / details / help or (y Id/n/d/h) - if yes Ids, update chosen set
 :
```
Typing `yes`, or `y` will proceed with update, update can be limited to a chosen set by passing Id
indicating actions just after `yes`, e.g. `yes 1`, `yes 2 5`.

The prompt can be skipped with:
```bash
# Update Sets without prompt
nftlist update
# or shorter
nftlist u
```
This will proceed with updates without prompting.

By default, configuration from `/etc/nftlists/available/` is loaded, but it can be overwritten:
```bash
nftlist update --config /etc/my_list.list
# or
nftlist update --config /etc/my_list_directory/
# additionally include directory can be indicated:
nftlist update --config /etc/my_list.list --include /etc/incl_lists/
# or shortly:
nftlist update -c /etc/my_list.list -i /etc/incl_lists/
```
`nftlist` comes with `panic` option that will apply policies defined by `\@onpanic` directive.

## Periodic runs

`A` or `AAAA` records can change over time, therefore firewall shall be updated periodically.
It is advised to add to daily cron `service nftlist reload` so configuration shall be keep in
sync with DNS entries.

## White List example

One of the example of whitelisting is to allow outgoing connections to be only possible with a
very limited number of servers. This can be a list of a domain names that are used for system updates.
The configuration might look as bellow:
```
# file: /etc/nftlists/available/repo_devuan.list

# Devuan repositories
deb.devuan.org
deb.debian.org
```
```
# file: /etc/nftlists/enabled/

@set inet filter allow_outgoing
@ include repo_devuan.list
```
We can white list more resources:
```
# file: /etc/nftlists/enabled/

@set inet filter allow_outgoing
@ include repo_devuan.list
10.2.0.100
example.com
```
Note that by splitting configuration to a set of files it become more manageable.
Also note, that you can mix domain names with IP address.

NFT rule bound to `allow_outgoing` set would be defined in forward chain. The default policy for that chain might be `drop`, the
rule might be as follows:
```
iifname br0 oifname eth0 ip daddr @allow_outgoing tcp dport { 80, 443 } accept
```


## Troubleshooting
In the case of troubles you run:
```
nftlist --verbose
```
And check for any detailed error messages. If it does not help analyze what exactly is under the hood:

```bash
# Stop firewall
service nftlist stop
service nftables stop

# checkout defined rules
# it should be empty
nft list ruleset

# start firewall
service nftables stop

# analyze configuration
nft list ruleset

# start nftlist
service nftlist start

# and verify if sets has been updated
nft list ruleset
```
also you can:
```bash
# List all sets
nft list sets

# Add set elements manually
nft add element inet my_table allowed_hosts { 172.22.0.2 }
```
NFT provides [counters](https://wiki.nftables.org/wiki-nftables/index.php/Counters), it can give you some information if
traffic is passing trough certain firewall rule or hook.
In tha case of troubles tools such as tcpdump and WireShark come in handy.

# Summary

NFT Helper is useful with containerization/virtualisation technics where running VMs can be limited to exact network resources they need. I developed it to have a lite, robust and straight-forward solution for various  NFT firewall cases.

# Useful links

**HowTo:**

* Nftables Wiki [here](https://wiki.nftables.org/)
* Gentoo Nftables guide (nice and compact) [here](https://wiki.gentoo.org/wiki/Nftables)
* and Arch Linux NFT (alike Gentoo's wiki, but nothing about howto compile kernel :) [wiki](https://wiki.archlinux.org/title/Nftables)

**Theory:**

* Netfilter framework [at Wikipedia](https://en.wikipedia.org/wiki/Netfilter)


**Practice**
[serverfault: nftables: referencing a set from another table](https://serverfault.com/questions/1145318/nftables-referencing-a-set-from-another-table)

**Bad addresses databases**
Phishing Database: [github: mitchellkrogza/Phishing.Database](https://github.com/mitchellkrogza/Phishing.Database/)

