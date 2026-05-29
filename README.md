# dokku-shared-rabbitmq

Shared, multi-tenant RabbitMQ plugin for Dokku. One RabbitMQ container
per host; per-tenant isolation via **native vhosts** with scoped
permissions. Plugin-level message-count quota enforcement via cron.

**Status:** scaffolded 2026-05-30. v0.1.0 not yet built. See `CLAUDE.md`
for the complete onboarding brief.

## Why

Companion to:

- [dokku-shared-postgres](https://github.com/johannesdwicahyo/dokku-shared-postgres)
- [dokku-shared-redis](https://github.com/johannesdwicahyo/dokku-shared-redis)
- [dokku-shared-minio](https://github.com/johannesdwicahyo/dokku-shared-minio)
- [dokku-shared-memcached](https://github.com/johannesdwicahyo/dokku-shared-memcached)

Backs the every-box-includes-RabbitMQ tier in
[Wokku Cloud](https://wokku.cloud) plans (bundle v2).

## License

MIT (target).
