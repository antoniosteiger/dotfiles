# PostgreSQL + Redis, both on the NVMe, both reached over unix sockets only.
#
# Nextcloud and Paperless use peer authentication over /run/postgresql (their
# `database.createLocally`), so there are no database passwords to manage or leak.
# Tuned for an 8 GB box that also runs PHP-FPM and OCR.
{ pkgs, ... }:
{
  services.postgresql = {
    enable = true;
    # Pinned: a PostgreSQL major upgrade is a manual dump/restore (or pg_upgrade) job and
    # must never happen as a side effect of an unattended flake update.
    package = pkgs.postgresql_17;
    settings = {
      max_connections = 60;
      shared_buffers = "512MB";
      effective_cache_size = "3GB";
      work_mem = "16MB";
      maintenance_work_mem = "128MB";
      random_page_cost = 1.1; # NVMe
      effective_io_concurrency = 200;
      checkpoint_completion_target = 0.9;
      wal_compression = "on";
      log_min_duration_statement = 1000;
    };
  };

  # The Nextcloud module creates redis-nextcloud (unix socket, port 0); just cap it.
  services.redis.servers.nextcloud.settings = {
    maxmemory = "256mb";
    maxmemory-policy = "volatile-lru";
  };
}
