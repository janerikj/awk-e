# Examples

This directory is not loaded by default. Point awk-e at it with
`-r examples` (there is deliberately no default rule directory, so a live input
cannot trigger an example rule by accident). The rules here double as a
starting point for your own.

```shell
./awk-e -l -r examples                 # what is in here
./awk-e -n -r examples -i messages.log # dry run against the recording
./awk-e -v -r examples -i messages.log # the same, with routing logged
./awk-e -r examples --tick 2                 # the clock alone
./awk-e -n -r examples --mqtt -h mqtt.local  # live, dry run against a broker
./awk-e -r examples --mqtt -h mqtt.local --tick 2   # live, with a clock
```

| File | Shows |
| --- | --- |
| `temp.awk` | state between messages: alerts on the rising edge, not on every reading |
| `door.awk` | state changes, retained messages, `emit()` for an arbitrary command |
| `json.awk` | a JSON topic extracted by `json()`, so the handler sees plain text |
| `chain.awk` | one reading split into internal events with `chain()`, handled by other rules |
| `mqtt.awk` | the MQTT topic filter (`+`, `#`) that `reg()` takes by default |
| `heartbeat.awk` | scheduled work from the built-in clock, publishing a heartbeat topic |
| `modbus.sh` | a `--pipe` poll: one register read per row of `modbus.map`, printed as topics |
| `modbus.map` | the register map (`slave type addr count fmt topic`) the recipe reads |
| `ntfy-pipe.sh` | a `--pipe` subscription to an ntfy topic, printed as `ntfy/<topic> payload` |
| `messages.log` | a recorded `mosquitto_sub -F '%t %p'` stream used by `--input` |

Point a real broker at them and publish:

```shell
mosquitto_pub -t home/kitchen/temp -m 33.5
mosquitto_pub -t home/door -m open
mosquitto_pub -t home/sensor/json -m '{"temperature": 31.2, "humidity": 44}'
```

Without `--dry-run` the actions run for real: they publish back to the broker
and hand the door state to `logger`.

## `heartbeat.awk`

Runs on the clock from `--tick` / `AWKE_TICK` instead of on broker traffic,
which is the only way to get periodic work out of a router that also has to stay
quiet while nothing happens. The rule can be tested offline, because a tick is
just a line in a recording:

```shell
echo 'awk-e/tick/2026-10-03T11:22:33Z 1756899753' | ./awk-e -n -q -i -
```

## `modbus.sh`

A `--pipe` recipe that turns a Modbus/TCP device into topics: for each row of
`modbus.map` it runs one `mbpoll` read and prints the value as `topic payload`.
Different register types need different reads, so the map's `type` column picks
the Modbus function code.

```shell
awk-e --pipe './examples/modbus.sh 10.0.0.5' --every 5 --changed
```

It needs `mbpoll` (not an awk-e dependency): `sudo apt install mbpoll`.
`MODBUS_HOST`, `MODBUS_PORT` (default 502) and `MODBUS_MAP` set the defaults.
`./examples/modbus.sh --help` (or `-?`) explains the map columns and options.

## `ntfy-pipe.sh`

A long-lived `--pipe` recipe for ntfy: it reads a topic's JSON stream and prints
each message as `ntfy/<topic> payload`. Newlines in the message are escaped, so
one ntfy message stays one line for awk-e.

```shell
awk-e --pipe './examples/ntfy-pipe.sh mytopic'
```

Do not add `--every`: ntfy pushes the stream, it is not polled. If the connection
drops, the recipe exits and `Restart=always` in the service unit starts it again.

It needs `curl` and `jq` (not awk-e dependencies): `sudo apt install curl jq`.
`NTFY_URL` points at another server, `NTFY_PREFIX` changes the topic prefix, and
`NTFY_USER`/`NTFY_PASS` or `NTFY_TOKEN` add authentication. `NTFY_SINCE` replays
from a timestamp or message id before continuing. ntfy.sh topics are public by
default, so use an unguessable name or a self-hosted/authenticated server.
`./examples/ntfy-pipe.sh --help` (or `-?`) lists the variables and defaults.

## `messages.log`

Exactly what `mosquitto_sub -F '%t %p'` prints, one `topic payload` per line.
An empty payload is a bare topic line. Record your own with:

```shell
mosquitto_sub -F '%t %p' -t '#' | tee my.log
./awk-e -n -i my.log
```

## `awk-e.service`

A systemd unit. It assumes the script in `/usr/local/bin/awk-e`, rules in
`/etc/awk-e/rules` and configuration in `/etc/awk-e/.env`. See the
deployment section in [../README.md](../README.md).

## Your own rules

Copy the directory, delete what you do not need and keep what you do:

```shell
cp -r examples ~/rules && rm ~/rules/json.awk
$EDITOR ~/rules/door.awk
./awk-e -r ~/rules -n -i ~/rules/recording.log
```