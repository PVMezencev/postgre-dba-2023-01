## Журналы.

1. Настроим выполнение контрольной точки раз в 30 сек:
    ```bash
    devops0@otus-pg:~$ sudo nano /etc/postgresql/14/main/postgresql.conf
    ```
    - Изменим значение:
    ```bash
    checkpoint_timeout = 30s         # range 30s-1d
    ```
    - Перезапустим кластер для применения настройки:
    ```bash
    devops0@otus-pg:~$ sudo -u postgres pg_ctlcluster 14 main restart
    ```
    - Проверим состояние кластера:
    ```bash
    devops0@otus-pg:~$ sudo -u postgres pg_lsclusters
    Ver Cluster Port Status Owner    Data directory              Log file
    14  main    5432 online postgres /var/lib/postgresql/14/main /var/log/postgresql/postgresql-14-main.log
    ```
    - Подключимся к кластеру, создадим тестовую БД с таблицей и заполним её тестовыми данными:
    ```bash
    devops0@otus-pg:~$ sudo -u postgres psql
    
    postgres=# \c buffer_temp;
    
    buffer_temp=# CREATE TABLE test(i int);
    CREATE TABLE
    buffer_temp=# INSERT INTO test SELECT s.id FROM generate_series(1,500) AS s(id); 
    INSERT 0 500
    buffer_temp=# SELECT * FROM test limit 10;
      1
      2
      3
      4
      5
      6
      7
      8
      9
     10
    
    buffer_temp=# \q
    ```
   
_После нескольких попыток выполнения ДЗ по порядку, пришел к выводу, что 2 и 4 пункты нужно объединить._

2. (и 4)Для удобства выполнения команд запустим оболочку bash от пользователя postgres:
    ```bash
    devops0@otus-pg:~$ sudo -u postgres -i
    ```

    - До выполнения тестов выведем текущую позицию добавления в журнале предзаписи, чтоб потом можно было вычислить объем записанных в журнал данных:
    
    ```bash
    postgres@otus-pg:~$ psql -c "SELECT pg_current_wal_insert_lsn();"
    pg_current_wal_insert_lsn
    ---------------------------
    0/16FB6B8
    (1 row)
    ```

    - Чтоб зафиксировать статистику до тестирования и сразу после неё выполним последовательно следующее: сбросим данные статистики, выведем статистику в консоль, запустим тест, выведем снова статистику:
    
    ```bash
    postgres@otus-pg:~$ psql -c "SELECT pg_stat_reset_shared('bgwriter');" && psql -c '\gx' -c 'SELECT * FROM pg_stat_bgwriter;' && pgbench -P 60 -T 600 buffer_temp && psql -c '\gx' -c 'SELECT * FROM pg_stat_bgwriter;'
    ```
    
    - Последовательно опишу результат, вывод статистики до тестирования:
    ```bash
     pg_stat_reset_shared
    ----------------------
    
    (1 row)
    
    -[ RECORD 1 ]---------+------------------------------
    checkpoints_timed     | 0
    checkpoints_req       | 0
    checkpoint_write_time | 0
    checkpoint_sync_time  | 0
    buffers_checkpoint    | 0
    buffers_clean         | 0
    maxwritten_clean      | 0
    buffers_backend       | 0
    buffers_backend_fsync | 0
    buffers_alloc         | 0
    stats_reset           | 2023-03-08 01:05:10.991305+05
    
    ```
    
    - Тестирование 600 сек, на каждой 60 сек печатать промежуточный результат:
    ```bash
    pgbench (14.7 (Debian 14.7-1.pgdg110+1))
    starting vacuum...end.
    progress: 60.0 s, 253.4 tps, lat 3.945 ms stddev 0.787
    progress: 120.0 s, 247.0 tps, lat 4.047 ms stddev 0.750
    progress: 180.0 s, 247.0 tps, lat 4.049 ms stddev 0.715
    progress: 240.0 s, 246.3 tps, lat 4.059 ms stddev 0.732
    progress: 300.0 s, 246.7 tps, lat 4.052 ms stddev 0.712
    progress: 360.0 s, 244.6 tps, lat 4.088 ms stddev 0.743
    progress: 420.0 s, 245.3 tps, lat 4.076 ms stddev 0.756
    progress: 480.0 s, 245.0 tps, lat 4.081 ms stddev 0.757
    progress: 540.0 s, 247.9 tps, lat 4.034 ms stddev 0.783
    progress: 600.0 s, 244.6 tps, lat 4.088 ms stddev 0.777
    transaction type: <builtin: TPC-B (sort of)>
    scaling factor: 1
    query mode: simple
    number of clients: 1
    number of threads: 1
    duration: 600 s
    number of transactions actually processed: 148071
    latency average = 4.052 ms
    latency stddev = 0.753 ms
    initial connection time = 5.047 ms
    tps = 246.785711 (without initial connection time)
    
    ```
    
    - Вывод статистики после тестирования:
    ```bash
    -[ RECORD 1 ]---------+------------------------------
    checkpoints_timed     | 20
    checkpoints_req       | 0
    checkpoint_write_time | 538065
    checkpoint_sync_time  | 656
    buffers_checkpoint    | 33027
    buffers_clean         | 0
    maxwritten_clean      | 0
    buffers_backend       | 952
    buffers_backend_fsync | 0
    buffers_alloc         | 947
    stats_reset           | 2023-03-08 01:05:10.991305+05
    
    ```

**Вывод:**
Интересны параметры: checkpoints_timed (Количество запланированных контрольных точек, которые уже были выполнены), 
checkpoint_sync_time (Общее время, которое было затрачено на этап обработки контрольной точки, в котором файлы 
синхронизируются с диском, в миллисекундах) и checkpoint_write_time (Общее время, которое было затрачено на этап 
обработки контрольной точки, в котором файлы записываются на диск, в миллисекундах). 
[Описание подсмотрено в документации postgrespro.ru](https://postgrespro.ru/docs/postgresql/14/monitoring-stats). 
Как видим, за время тестирования успели **выполниться все 20 точек (600 сек по 1 точке раз в 30 сек = 20 точек)**.
Посчитаем примерное время на выполнение точек (538065 + 656) / 1000 / 20 = **26,936 сек**, что укладывается 
в заданные параметры кластера (30 сек).

3. Измерим объем журнальных файлов на контрольную точку:
    - Выведем текущую позицию добавления в журнале предзаписи:

    ```bash
    postgres@otus-pg:~$ psql -c "SELECT pg_current_wal_insert_lsn();"
    pg_current_wal_insert_lsn
    ---------------------------
    0/16537010
    (1 row)
    ```
    - Вычислим объем из разницы позиций:

    ```bash
    postgres@otus-pg:~$ psql -c "SELECT pg_size_pretty('0/16537010'::pg_lsn - '0/16FB6B8'::pg_lsn);"
    pg_current_wal_insert_lsn
    ---------------------------
    334 MB
    (1 row)
    ```
   **Вывод:**
    Было сгенерировано 334 мегабайта данных. 334 MB / 20 точек = **16,7 MB на точку** в среднем.

4. Объединен со вторым.
5. Сравнение тестов нагрузки в синхронном/асинхронном режимах:

    - Посмотрим параметр настройки режима в файле конфигурации - по умолчанию включен синхронный режим:
    ```bash
   postgres@otus-pg:~$ cat /etc/postgresql/14/main/postgresql.conf | grep synchronous_commit
    #synchronous_commit = on		# synchronization level; 
   ```
    - Посмотрим параметр настройки режима в настройках кластера - включен синхронный режим:
    ```bash
   postgres@otus-pg:~$ psql -c "select name, setting from pg_settings where name = 'synchronous_commit';"
        name        | setting
    --------------------+---------
    synchronous_commit | on
    (1 row)
   ```
    - Выключим синхронный режим:
    ```bash
   postgres@otus-pg:~$ psql -c "ALTER SYSTEM SET synchronous_commit = off;"
   ALTER SYSTEM
   ```
    - Перезагрузим кластер, чтоб применить измененные параметры и проверим сразу - синхронный режим выключился:
    ```bash
   postgres@otus-pg:~$ pg_ctlcluster 14 main reload
   postgres@otus-pg:~$ psql -c "select name, setting from pg_settings where name = 'synchronous_commit';"
           name        | setting
    --------------------+---------
    synchronous_commit | off
    (1 row)
   ```
    - Запустим нагрузку:
    ```bash
    postgres@otus-pg:~$ pgbench -P 60 -T 600 buffer_temp
    pgbench (14.7 (Debian 14.7-1.pgdg110+1))
    starting vacuum...end.
    progress: 60.0 s, 1501.2 tps, lat 0.666 ms stddev 0.117
    progress: 120.0 s, 1499.7 tps, lat 0.666 ms stddev 0.115
    progress: 180.0 s, 1498.3 tps, lat 0.667 ms stddev 0.112
    progress: 240.0 s, 1501.0 tps, lat 0.666 ms stddev 0.114
    progress: 300.0 s, 1506.3 tps, lat 0.664 ms stddev 0.136
    progress: 360.0 s, 1497.5 tps, lat 0.667 ms stddev 0.107
    progress: 420.0 s, 1496.6 tps, lat 0.668 ms stddev 0.111
    progress: 480.0 s, 1488.7 tps, lat 0.671 ms stddev 0.111
    progress: 540.0 s, 1491.6 tps, lat 0.670 ms stddev 0.114
    progress: 600.0 s, 1480.1 tps, lat 0.675 ms stddev 0.117
    transaction type: <builtin: TPC-B (sort of)>
    scaling factor: 1
    query mode: simple
    number of clients: 1
    number of threads: 1
    duration: 600 s
    number of transactions actually processed: 897672
    latency average = 0.668 ms
    latency stddev = 0.116 ms
    initial connection time = 5.655 ms
    tps = 1496.130613 (without initial connection time)
   ```
   **Вывод:**
    **Скорость выполнения операций увеличилась почти в ~6 раз** в 1496.130613 / 246.785711 = 6,062468556. Асинхронный 
режим позволяет сократить время на операцию, но не гарантирует сохранность данных в случае сбойной ситуации. Такой режим
нельзя использовать для критически важных данных, например для финансовых операций, но зато он вполне подойдёт для 
операций логирования или сбора статистики, где потеря некоторой доли данных не критична (навеяло TCP и UDP аналогию).

6. Имитация сбойной ситуации:
    - Создадим новый кластер:
    ```bash
    postgres@otus-pg:~$ pg_createcluster 14 20230307
    Creating new PostgreSQL cluster 14/20230307 ...
    /usr/lib/postgresql/14/bin/initdb -D /var/lib/postgresql/14/20230307 --auth-local peer --auth-host scram-sha-256 --no-instructions
    The files belonging to this database system will be owned by user "postgres".
    This user must also own the server process.
    
    The database cluster will be initialized with locales
    COLLATE:  en_US.UTF-8
    CTYPE:    en_US.UTF-8
    MESSAGES: en_US.UTF-8
    MONETARY: ru_RU.UTF-8
    NUMERIC:  ru_RU.UTF-8
    TIME:     ru_RU.UTF-8
    The default database encoding has accordingly been set to "UTF8".
    The default text search configuration will be set to "english".
    
    Data page checksums are disabled.
    
    fixing permissions on existing directory /var/lib/postgresql/14/20230307 ... ok
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
    14  20230307 5433 down   postgres /var/lib/postgresql/14/20230307 /var/log/postgresql/postgresql-14-20230307.log

    ```
    - Управление настройкой контрольной суммы страниц можно произвести утилитой pg_checksums, 
   она находится в каталоге /usr/lib/postgresql/14/bin (для 14 версии) и может быть недоступна в переменной окружения $PATH:
    ```bash
    postgres@otus-pg:~$ pg_checksums
    -bash: pg_checksums: command not found
   devops0@otus-pg:~$ sudo ls -la /usr/lib/postgresql/14/bin | grep checksums
    -rwxr-xr-x 1 root root   64048 фев  7 19:25 pg_checksums
    ```
   - Включим проверку контрольной суммы для созданного кластера:
    ```bash
    devops0@otus-pg:~$ sudo /usr/lib/postgresql/14/bin/pg_checksums --enable -D /var/lib/postgresql/14/20230307/
    Checksum operation completed
    Files scanned:  931
    Blocks scanned: 3216
    pg_checksums: syncing data directory
    pg_checksums: updating control file
    Checksums enabled in cluster
   ```
   - Запустим кластер:
    ```bash
    postgres@otus-pg:~$ pg_ctlcluster 14 20230307 start
    Warning: the cluster will not be running as a systemd service. Consider using systemctl:
    sudo systemctl start postgresql@14-20230307
   ```
   - Проверим состояние кластеров в системе:
    ```bash
    postgres@otus-pg:~$ pg_lsclusters
    Ver Cluster  Port Status Owner    Data directory                  Log file
    14  20230307 5433 online postgres /var/lib/postgresql/14/20230307 /var/log/postgresql/postgresql-14-20230307.log
    14  main     5432 online postgres /var/lib/postgresql/14/main     /var/log/postgresql/postgresql-14-main.log

   ```
   - Подключимся к кластеру и проверим состояние настройки контрольной суммы - включена:
    ```bash
    postgres@otus-pg:~$ psql -p 5433
    psql (15.2 (Debian 15.2-1.pgdg110+1), server 14.7 (Debian 14.7-1.pgdg110+1))
    Type "help" for help.
    
    postgres=# SHOW data_checksums;
    data_checksums
    ----------------
    on
    (1 row)
   ```
   - Создадим тестовую таблицу и наполним её тестовыми данными, сразу проверим:
    ```bash
    postgres=# CREATE TABLE test_text(t text);
    CREATE TABLE
    postgres=# INSERT INTO test_text SELECT 'строка '||s.id FROM generate_series(1,500) AS s(id);
    INSERT 0 500
    postgres=# SELECT * FROM test_text limit 10;
    t
    -----------
    строка 1
    строка 2
    строка 3
    строка 4
    строка 5
    строка 6
    строка 7
    строка 8
    строка 9
    строка 10
    (10 rows)
   ```
   - Получим путь к файлу таблицы:
    ```bash
    postgres=# SELECT pg_relation_filepath('test_text');
    pg_relation_filepath
    ----------------------
    base/13759/16384
    (1 row)
   ```
   - Остановим подопытный кластер и проверим его состояние:
    ```bash
    postgres@otus-pg:~$ pg_ctlcluster 14 20230307 stop
    postgres@otus-pg:~$ pg_lsclusters
    Ver Cluster  Port Status Owner    Data directory                  Log file
    14  20230307 5433 down   postgres /var/lib/postgresql/14/20230307 /var/log/postgresql/postgresql-14-20230307.log
    14  main     5432 online postgres /var/lib/postgresql/14/main     /var/log/postgresql/postgresql-14-main.log

   ```
   - Чтоб имитировать потерю данных при аварийном выключении заменим первые 8 байт файла таблицы нулями:
    ```bash
    postgres@otus-pg:~$ dd if=/dev/zero of=/var/lib/postgresql/14/20230307/base/13759/16384 oflag=dsync conv=notrunc bs=1 count=8
    8+0 records in
    8+0 records out
    8 bytes copied, 0,0365031 s, 0,2 kB/s
   ```
   - Запустим подопытный кластер и проверим его состояние:
    ```bash
    postgres@otus-pg:~$ pg_ctlcluster 14 20230307 start
    Warning: the cluster will not be running as a systemd service. Consider using systemctl:
    sudo systemctl start postgresql@14-20230307
    postgres@otus-pg:~$ pg_lsclusters
    Ver Cluster  Port Status Owner    Data directory                  Log file
    14  20230307 5433 online postgres /var/lib/postgresql/14/20230307 /var/log/postgresql/postgresql-14-20230307.log
    14  main     5432 online postgres /var/lib/postgresql/14/main     /var/log/postgresql/postgresql-14-main.log

   ```
   - Подключимся к кластеру, попробуем сделать выборку из тестовой таблицы:
    ```bash
    postgres@otus-pg:~$ psql -p 5433
    postgres=# SELECT * FROM test_text limit 10;
    WARNING:  page verification failed, calculated checksum 15585 but expected 48520
    ERROR:  invalid page in block 0 of relation base/13759/16384

   ```
   Получаем ошибку в контрольных суммах таблицы - при штатной работе была сохранена сумма 48520, при попытке сделать запрос
получили сумму 15585. Таким образом механизм контроля вычисляет повреждение данных и не позволяет получить их.
    - Чтоб игнорировать эту ошибку, можно включить параметр ignore_checksum_failure, он работает только когда включен механизм
   проверки контрольной суммы:
    ```bash
   postgres=# SELECT name, setting FROM pg_settings WHERE name = 'ignore_checksum_failure';
          name           | setting 
    -------------------------+---------
    ignore_checksum_failure | off
    (1 row)

    postgres=# SET ignore_checksum_failure = on;
    SET
    postgres=# SELECT name, setting FROM pg_settings WHERE name = 'ignore_checksum_failure';
          name           | setting 
    -------------------------+---------
    ignore_checksum_failure | on
    (1 row)
   ```
    - Попробуем сделать выборку:
    ```bash
    postgres=# SELECT * FROM test_text limit 10;
    WARNING:  page verification failed, calculated checksum 15585 but expected 48520
    t
    -----------
    строка 1
    строка 2
    строка 3
    строка 4
    строка 5
    строка 6
    строка 7
    строка 8
    строка 9
    строка 10
    (10 rows)

   ```
   Ошибка игнорируется, данные получены, но получено и предупреждение о не соответствии контрольной суммы.
    - Для восстановления контрольной суммы сделаем фиктивное обновление данных:
    ```bash
    postgres=# UPDATE test_text SET t = 'строка 1' where t='строка 1';
    UPDATE 1

   ```
    - Попробуем выбрать данные ещё раз:
    ```bash
    postgres=# SELECT * FROM test_text limit 10;
    t
    -----------
    строка 2
    строка 3
    строка 4
    строка 5
    строка 6
    строка 7
    строка 8
    строка 9
    строка 10
    строка 11
    (10 rows)
   
   #  Первая строка не исчезла, она переместилась в порядке выборки, мы увидим её, если изменим порядок сортировки:
    postgres=# SELECT * FROM test_text ORDER BY t limit 10;
    t
    ------------
    строка 1
    строка 10
    строка 100
    строка 101
    строка 102
    строка 103
    строка 104
    строка 105
    строка 106
    строка 107
    (10 rows)

   ```
   Предупреждение исчезло, потому что при обновлении контрольная сумма обновилась тоже.
    - Отключим игнорирование ошибок:
    ```bash
    postgres=# SET ignore_checksum_failure = off;
    SET

   ```
    - Попробуем выбрать данные ещё раз:
    ```bash
    postgres=# SELECT * FROM test_text limit 10;
    t
    -----------
    строка 2
    строка 3
    строка 4
    строка 5
    строка 6
    строка 7
    строка 8
    строка 9
    строка 10
    строка 11
    (10 rows)

   ```
   Данные получены, контрольная сумма восстановлена. В данном случае нам повезло, так как были искажены только байты 
заголовков таблицы, а сами данные остались целыми.
    
   
   
