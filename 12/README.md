## Настройка PostgreSQL.

1. Воспользуемся существующей ВМ:
    ```text
    -- DB Version: 15
    -- OS Type: linux (Debian 11)
    -- DB Type: web
    -- Total Memory (RAM): 2 GB
    -- CPUs num: 1
    -- Connections num: 100
    -- Data Storage: ssd
    ```
2. Установлен PostgreSQL 15 из официальных репозиториев ОС через утилиту apt.
3. Займемся настройкой кластера:
    - Создадим новый кластер:
    ```bash
    devops0@otus-pg:~$ sudo -u postgres pg_createcluster 15 20230318
    Creating new PostgreSQL cluster 15/20230318 ...
    /usr/lib/postgresql/15/bin/initdb -D /var/lib/postgresql/15/20230318 --auth-local peer --auth-host scram-sha-256 --no-instructions
    The files belonging to this database system will be owned by user "postgres".
    This user must also own the server process.
    
    The database cluster will be initialized with this locale configuration:
    provider:    libc
    LC_COLLATE:  en_US.UTF-8
    LC_CTYPE:    en_US.UTF-8
    LC_MESSAGES: en_US.UTF-8
    LC_MONETARY: ru_RU.UTF-8
    LC_NUMERIC:  ru_RU.UTF-8
    LC_TIME:     ru_RU.UTF-8
    The default database encoding has accordingly been set to "UTF8".
    The default text search configuration will be set to "english".
    
    Data page checksums are disabled.
    
    fixing permissions on existing directory /var/lib/postgresql/15/20230318 ... ok
    creating subdirectories ... ok
    selecting dynamic shared memory implementation ... posix
    selecting default max_connections ... 100
    selecting default shared_buffers ... 128MB
    selecting default time zone ... Asia/Yekaterinburg
    creating configuration files ... ok
    running bootstrap script ... ok
    performing post-bootstrap initialization ... ok
    syncing data to disk ... ok
    Warning: systemd does not know about the new cluster yet. Operations like "service postgresql start" will not handle it. To fix, run:
    sudo systemctl daemon-reload
    Ver Cluster  Port Status Owner    Data directory                  Log file
    15  20230318 5432 down   postgres /var/lib/postgresql/15/20230318 /var/log/postgresql/postgresql-15-20230318.log
    
    devops0@otus-pg:~$ sudo -u postgres pg_ctlcluster 15 20230318 start
    Warning: the cluster will not be running as a systemd service. Consider using systemctl:
    sudo systemctl start postgresql@15-20230318
    
    devops0@otus-pg:~$ sudo -u postgres pg_lsclusters
    Ver Cluster  Port Status Owner    Data directory                  Log file
    15  20230318 5432 online postgres /var/lib/postgresql/15/20230318 /var/log/postgresql/postgresql-15-20230318.log

   ```
    - Для удобства авторизуемся под пользователем postgres:
    ```bash
    devops0@otus-pg:~$ sudo -u postgres -i
    postgres@otus-pg:~$ pg_lsclusters
    Ver Cluster  Port Status Owner    Data directory                  Log file
    15  20230318 5432 online postgres /var/lib/postgresql/15/20230318 /var/log/postgresql/postgresql-15-20230318.log

   ```
    - Инициализируем необходимые тестовые данные:
    ```bash
    postgres@otus-pg:~$ pgbench -i -s 500 --foreign-keys postgres
    dropping old tables...
    creating tables...
    generating data (client-side)...
    50000000 of 50000000 tuples (100%) done (elapsed 189.46 s, remaining 0.00 s)
    vacuuming...
    creating primary keys...
    creating foreign keys...
    done in 268.51 s (drop tables 0.02 s, create tables 0.02 s, client-side generate 189.95 s, vacuum 1.11 s, primary keys 62.53 s, foreign keys 14.88 s).

    # коэффициент масштаба заполнения таблиц возьмём 500, чтоб сгенерировать побольше данных, так же укажем, что будем использовать внешние ключи.
   ```
    - Проверим, что получилось:
    ```bash
    postgres@otus-pg:~$ psql
    psql (15.2 (Debian 15.2-1.pgdg110+1))
    Type "help" for help.
    
    postgres=# SELECT relname,n_live_tup
    FROM pg_stat_user_tables;
    relname      | n_live_tup
    ------------------+------------
    pgbench_accounts |   50000053
    pgbench_tellers  |       5000
    pgbench_branches |        500
    pgbench_history  |          0
    (4 rows)
   
    postgres=# \q
   ```
    - Запустим тест на дефолтных настройках кластера (Тест 1):
    ```bash
    postgres@otus-pg:~$ pgbench -c16 -P 60 -T 600 postgres
    pgbench (15.2 (Debian 15.2-1.pgdg110+1))
    starting vacuum...end.
    progress: 60.0 s, 679.2 tps, lat 20.978 ms stddev 38.546, 0 failed
    progress: 120.0 s, 661.2 tps, lat 21.740 ms stddev 35.571, 0 failed
    progress: 180.0 s, 646.1 tps, lat 22.363 ms stddev 48.904, 0 failed
    progress: 240.0 s, 641.2 tps, lat 22.567 ms stddev 52.445, 0 failed
    progress: 300.0 s, 640.6 tps, lat 22.483 ms stddev 50.943, 0 failed
    progress: 360.0 s, 643.9 tps, lat 22.510 ms stddev 50.080, 0 failed
    progress: 420.0 s, 656.9 tps, lat 21.949 ms stddev 36.582, 0 failed
    progress: 480.0 s, 658.4 tps, lat 21.920 ms stddev 35.993, 0 failed
    progress: 540.0 s, 663.6 tps, lat 21.694 ms stddev 37.081, 0 failed
    progress: 600.0 s, 670.0 tps, lat 21.489 ms stddev 34.138, 0 failed
    transaction type: <builtin: TPC-B (sort of)>
    scaling factor: 500
    query mode: simple
    number of clients: 16
    number of threads: 1
    maximum number of tries: 1
    duration: 600 s
    number of transactions actually processed: 393691
    number of failed transactions: 0 (0.000%)
    latency average = 21.960 ms
    latency stddev = 42.513 ms
    initial connection time = 59.894 ms
    tps = 656.139538 (without initial connection time)

   ```
   Имитируем работу 16 клиентов в течение 10 минут:
   **656.139538** - транзакций в секунду
   **21.960 ms** - задержка
    - Проверим, что происходит в БД:
    ```bash
   postgres@otus-pg:~$ psql
   psql (15.2 (Debian 15.2-1.pgdg110+1))
   Type "help" for help.
   
   postgres=# SELECT relname,n_live_tup
   FROM pg_stat_user_tables;
   relname      | n_live_tup
   ------------------+------------
   pgbench_accounts |   50000053
   pgbench_tellers  |       5000
   pgbench_branches |        500
   pgbench_history  |     393691 <-- появились строки после тестирования.
   (4 rows)
   
   postgres=# SELECT pg_size_pretty(pg_database_size(current_database()));
   pg_size_pretty
   ----------------
   7545 MB <-- объём данных.
   (1 row)
   ```
    - Выведем текущие настройки:
    ```bash
   postgres=# select
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
   'checkpoint_timeout',
   'synchronous_commit');
   name              | setting | unit | vartype |  context
   --------------------------------+---------+------+---------+------------
   autovacuum                     | on      |      | bool    | sighup
   autovacuum_max_workers         | 3       |      | integer | postmaster
   autovacuum_naptime             | 60      | s    | integer | sighup
   autovacuum_vacuum_cost_delay   | 2       | ms   | real    | sighup
   autovacuum_vacuum_cost_limit   | -1      |      | integer | sighup
   autovacuum_vacuum_scale_factor | 0.2     |      | real    | sighup
   autovacuum_vacuum_threshold    | 50      |      | integer | sighup
   checkpoint_completion_target   | 0.9     |      | real    | sighup
   checkpoint_timeout             | 300     | s    | integer | sighup
   deadlock_timeout               | 1000    | ms   | integer | superuser
   default_statistics_target      | 100     |      | integer | user
   effective_cache_size           | 524288  | 8kB  | integer | user
   effective_io_concurrency       | 1       |      | integer | user
   log_autovacuum_min_duration    | 600000  | ms   | integer | sighup
   log_lock_waits                 | off     |      | bool    | superuser
   maintenance_work_mem           | 65536   | kB   | integer | user
   max_connections                | 100     |      | integer | postmaster
   max_wal_size                   | 1024    | MB   | integer | sighup
   min_wal_size                   | 80      | MB   | integer | sighup
   random_page_cost               | 4       |      | real    | user
   shared_buffers                 | 16384   | 8kB  | integer | postmaster
   synchronous_commit             | on      |      | enum    | user
   wal_buffers                    | 512     | 8kB  | integer | postmaster
   work_mem                       | 4096    | kB   | integer | user
   (23 rows)
   
   ```
    - Применим настройки, полученные на https://pgtune.leopard.in.ua/. Устанавливать будем 
через запросы ALTER SYSTEM SET, такие настройки сохраняются в специальном конфиг-файле (для нашего кластера 
/var/lib/postgresql/15/20230318/postgresql.auto.conf). Таким образом, основной конфиг кластера остается неизменным:
    ```sql
   -- PGTUNE:
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
   synchronous_commit = 'off'; -- отключим синхронность, это увеличит производительность.
    
   ```
    - Параметры max_connections, shared_buffers, wal_buffers - относятся к контексту postmaster и требуют перезагрузки
сервиса для применения новых настроек:
    ```bash
   postgres@otus-pg:~$ pg_ctlcluster 15 20230318 restart
   Warning: the cluster will not be running as a systemd service. Consider using systemctl:
   sudo systemctl restart postgresql@15-20230318
   postgres@otus-pg:~$ pg_lsclusters
   Ver Cluster  Port Status Owner    Data directory                  Log file
   15  20230318 5432 online postgres /var/lib/postgresql/15/20230318 /var/log/postgresql/postgresql-15-20230318.log

   ```
    - Проверим настройки:
    ```bash
   postgres@otus-pg:~$ psql
   
   postgres=# select
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
   'checkpoint_timeout',
   'synchronous_commit');
   
                 name              | setting | unit | vartype |  context
   --------------------------------+---------+------+---------+------------
   autovacuum                     | on      |      | bool    | sighup
   autovacuum_max_workers         | 3       |      | integer | postmaster
   autovacuum_naptime             | 60      | s    | integer | sighup
   autovacuum_vacuum_cost_delay   | 2       | ms   | real    | sighup
   autovacuum_vacuum_cost_limit   | -1      |      | integer | sighup
   autovacuum_vacuum_scale_factor | 0.2     |      | real    | sighup
   autovacuum_vacuum_threshold    | 50      |      | integer | sighup
   checkpoint_completion_target   | 0.9     |      | real    | sighup
   checkpoint_timeout             | 300     | s    | integer | sighup
   deadlock_timeout               | 1000    | ms   | integer | superuser
   default_statistics_target      | 100     |      | integer | user
   effective_cache_size           | 196608  | 8kB  | integer | user
   effective_io_concurrency       | 200     |      | integer | user
   log_autovacuum_min_duration    | 600000  | ms   | integer | sighup
   log_lock_waits                 | off     |      | bool    | superuser
   maintenance_work_mem           | 131072  | kB   | integer | user
   max_connections                | 100     |      | integer | postmaster
   max_wal_size                   | 4096    | MB   | integer | sighup
   min_wal_size                   | 1024    | MB   | integer | sighup
   random_page_cost               | 1.1     |      | real    | user
   shared_buffers                 | 65536   | 8kB  | integer | postmaster
   synchronous_commit             | off     |      | enum    | user
   wal_buffers                    | 2048    | 8kB  | integer | postmaster
   work_mem                       | 2621    | kB   | integer | user
   (23 rows)
   
   postgres=# \q
   ```
4. Тестирование:
   - Тест 2:

   ```bash
   postgres@otus-pg:~$ pgbench -c16 -P 60 -T 600 postgres
   pgbench (15.2 (Debian 15.2-1.pgdg110+1))
   starting vacuum...end.
   progress: 60.0 s, 938.4 tps, lat 10.010 ms stddev 19.466, 0 failed
   progress: 120.0 s, 846.8 tps, lat 11.754 ms stddev 53.650, 0 failed
   progress: 180.0 s, 853.4 tps, lat 11.690 ms stddev 63.939, 0 failed
   progress: 240.0 s, 846.2 tps, lat 11.721 ms stddev 60.053, 0 failed
   progress: 300.0 s, 820.1 tps, lat 12.541 ms stddev 73.324, 0 failed
   progress: 360.0 s, 837.0 tps, lat 12.126 ms stddev 83.693, 0 failed
   progress: 420.0 s, 861.7 tps, lat 11.411 ms stddev 59.418, 0 failed
   progress: 480.0 s, 889.4 tps, lat 11.053 ms stddev 48.792, 0 failed
   progress: 540.0 s, 908.8 tps, lat 10.696 ms stddev 43.003, 0 failed
   progress: 600.0 s, 874.6 tps, lat 11.344 ms stddev 53.970, 0 failed
   transaction type: <builtin: TPC-B (sort of)>
   scaling factor: 500
   query mode: simple
   number of clients: 16
   number of threads: 1
   maximum number of tries: 1
   duration: 600 s
   number of transactions actually processed: 520603
   number of failed transactions: 0 (0.000%)
   latency average = 11.409 ms
   latency stddev = 57.810 ms
   initial connection time = 57.836 ms
   tps = 867.650383 (without initial connection time)
   ```
   Получили увеличение производительности: **867.650383** - транзакций в секунду, и снизились задержки **11.409 ms**.
   - Теперь изменим настройки, полученные из предыдущих ДЗ:
    ```sql   
   ALTER SYSTEM SET
   -- полученные в Тест 5 домашнего задания MVCC, vacuum и autovacuum, показавшие лучший результат.
   autovacuum_naptime = '15.0';
   ALTER SYSTEM SET
   autovacuum_vacuum_threshold = '25';
   ALTER SYSTEM SET
   autovacuum_vacuum_scale_factor = '0.05';
   ALTER SYSTEM SET
   autovacuum_vacuum_cost_delay = '5.0';
   ALTER SYSTEM SET
   autovacuum_vacuum_cost_limit = '500';
    
   ```
   - Данные настройки применяются, если перечитать конфиг:
   ```bash
   postgres=# SELECT pg_reload_conf(); -- Попросим процессы сервере перечитать конфигурационные файлы.
   ```
   - Тест 3:
   ```bash
   postgres@otus-pg:~$ pgbench -c16 -P 60 -T 600 postgres
   pgbench (15.2 (Debian 15.2-1.pgdg110+1))
   starting vacuum...end.
   progress: 60.0 s, 933.5 tps, lat 10.138 ms stddev 36.100, 0 failed
   progress: 120.0 s, 839.0 tps, lat 11.965 ms stddev 69.134, 0 failed
   progress: 180.0 s, 924.3 tps, lat 10.406 ms stddev 37.801, 0 failed
   progress: 240.0 s, 932.6 tps, lat 10.185 ms stddev 25.280, 0 failed
   progress: 300.0 s, 892.1 tps, lat 11.158 ms stddev 60.144, 0 failed
   progress: 360.0 s, 934.5 tps, lat 10.247 ms stddev 32.332, 0 failed
   progress: 420.0 s, 935.1 tps, lat 10.147 ms stddev 21.045, 0 failed
   progress: 480.0 s, 936.2 tps, lat 10.233 ms stddev 42.679, 0 failed
   progress: 540.0 s, 909.5 tps, lat 10.691 ms stddev 41.020, 0 failed
   progress: 600.0 s, 886.8 tps, lat 10.984 ms stddev 55.452, 0 failed
   transaction type: <builtin: TPC-B (sort of)>
   scaling factor: 500
   query mode: simple
   number of clients: 16
   number of threads: 1
   maximum number of tries: 1
   duration: 600 s
   number of transactions actually processed: 547417
   number of failed transactions: 0 (0.000%)
   latency average = 10.597 ms
   latency stddev = 44.079 ms
   initial connection time = 75.126 ms
   tps = 912.365987 (without initial connection time)
   ```
   Получили увеличение производительности: **912.365987** - транзакций в секунду, и снизились задержки **10.597 ms**.
5. В большей части прирост производительности дает включение асинхронности (отключение синхронности) **synchronous_commit**,
настройки автоочистки позволяют сократить время, затрачиваемое на операции autovacuum.

