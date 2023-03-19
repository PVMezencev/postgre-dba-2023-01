-- DB Version: 15
-- OS Type: linux
-- DB Type: web
-- Total Memory (RAM): 2 GB
-- CPUs num: 1
-- Connections num: 100
-- Data Storage: ssd

select
       name, setting, unit, vartype, context
from pg_settings
where name in ('max_connections',
               'shared_buffers',
               'effective_cache_size',
               'maintenance_work_mem',
               'checkpoint_completion_target',
               'wal_buffers',
               'default_statistics_target',
               'random_page_cost',
               'effective_io_concurrency',
               'work_mem',
               'min_wal_size',
               'max_wal_size',
               'synchronous_commit',
               'autovacuum',
               'log_autovacuum_min_duration',
               'autovacuum_max_workers',
               'autovacuum_naptime',
               'autovacuum_vacuum_threshold',
               'autovacuum_vacuum_scale_factor',
               'autovacuum_vacuum_cost_delay',
               'autovacuum_vacuum_cost_limit',
               'log_lock_waits',
               'deadlock_timeout',
               'checkpoint_timeout');


ALTER SYSTEM SET
    max_connections = '100';
ALTER SYSTEM SET
    shared_buffers = '512MB';
ALTER SYSTEM SET
    effective_cache_size = '1536MB';
ALTER SYSTEM SET
    maintenance_work_mem = '128MB';
ALTER SYSTEM SET
    checkpoint_completion_target = '0.9';
ALTER SYSTEM SET
    wal_buffers = '16MB';
ALTER SYSTEM SET
    default_statistics_target = '100';
ALTER SYSTEM SET
    random_page_cost = '1.1';
ALTER SYSTEM SET
    effective_io_concurrency = '200';
ALTER SYSTEM SET
    work_mem = '2621kB';
ALTER SYSTEM SET
    min_wal_size = '1GB';
ALTER SYSTEM SET
    max_wal_size = '4GB';
ALTER SYSTEM SET
    synchronous_commit = 'off';
ALTER SYSTEM SET
    autovacuum_naptime = '15.0';
ALTER SYSTEM SET
    autovacuum_vacuum_threshold = '25';
ALTER SYSTEM SET
    autovacuum_vacuum_scale_factor = '0.05';
ALTER SYSTEM SET
    autovacuum_vacuum_cost_delay = '5.0';
ALTER SYSTEM SET
    autovacuum_vacuum_cost_limit = '500';