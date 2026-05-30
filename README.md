# dokku-shared-rabbitmq

A Dokku plugin providing **shared, multi-tenant RabbitMQ** on a single host.
One `rabbitmq:3-management` container per host; each tenant gets a native
**vhost** plus a user whose permissions are scoped to that vhost only — so one
tenant's queues, exchanges, and bindings are invisible to every other tenant.

Per-tenant **message quotas** are enforced by a cron sweep that revokes a
tenant's `write` permission while it is over cap and restores it when usage
drops.

## Install

```bash
dokku plugin:install https://github.com/johannesdwicahyo/dokku-shared-rabbitmq.git shared-rabbitmq
```

The install hook pulls the image, starts the shared container (with a 1 GB
memory cap and a persistent volume for queue durability), fixes data-dir
ownership, and installs a 5-minute quota cron.

## Usage

```bash
dokku shared-rabbitmq:create mytenant            # provision; prints RABBITMQ_URL
dokku shared-rabbitmq:link mytenant myapp        # set RABBITMQ_URL on the app
dokku shared-rabbitmq:info mytenant              # vhost, message count, quota, links
dokku shared-rabbitmq:set-quota mytenant 50000   # cap at 50k messages
dokku shared-rabbitmq:list                       # all tenants on this host
dokku shared-rabbitmq:unlink mytenant myapp
dokku shared-rabbitmq:destroy mytenant -f        # delete vhost + user (all queues!)
```

Run `dokku shared-rabbitmq:help` for the full command list.

`RABBITMQ_URL` looks like:

```
amqp://mytenant:<password>@dokku-shared-rabbitmq:5672/mytenant
```

The host (`dokku-shared-rabbitmq`) resolves on the shared Docker network that
linked apps join automatically. The last path segment is the tenant's vhost.

## Connecting from your app

**Python (pika):**

```python
import os, pika
params = pika.URLParameters(os.environ["RABBITMQ_URL"])
conn = pika.BlockingConnection(params)
channel = conn.channel()
channel.queue_declare(queue="jobs")
channel.basic_publish(exchange="", routing_key="jobs", body="hello")
```

**Node.js (amqplib):**

```js
const amqp = require("amqplib");
const conn = await amqp.connect(process.env.RABBITMQ_URL);
const channel = await conn.createChannel();
await channel.assertQueue("jobs");
channel.sendToQueue("jobs", Buffer.from("hello"));
```

**Ruby (bunny):**

```ruby
require "bunny"
conn = Bunny.new(ENV["RABBITMQ_URL"]).tap(&:start)
channel = conn.create_channel
queue = channel.queue("jobs")
channel.default_exchange.publish("hello", routing_key: queue.name)
```

## Isolation & quotas

- Each tenant = one vhost + one user with `set_permissions -p <vhost> <user> ".*" ".*" ".*"`.
- Over the message quota, write permission is revoked (`".*" "" ".*"`) until the
  next sweep finds usage back under cap; reads and connections keep working.
- The default cap is 10,000 messages; override per tenant with `set-quota`.

## Development

```bash
make lint   # shellcheck
make test   # bats unit tests
```

`tests/integration_smoke.sh` runs an end-to-end check on a real Dokku host.

## License

MIT.
