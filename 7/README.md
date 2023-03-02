## Логический уровень PostgreSQL

1. Создаём новый кластер PostgresSQL 14:
   - Собственно, создание:
    ```bash
    devops0@otus-pg:~$ sudo -u postgres pg_createcluster 14 20230302
    Creating new PostgreSQL cluster 14/20230302 ...
    /usr/lib/postgresql/14/bin/initdb -D /var/lib/postgresql/14/20230302 --auth-local peer --auth-host scram-sha-256 --no-instructions
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
    
    fixing permissions on existing directory /var/lib/postgresql/14/20230302 ... ok
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
    14  20230302 5434 down   postgres /var/lib/postgresql/14/20230302 /var/log/postgresql/postgresql-14-20230302.log
    ```
    - Выполним рекомендации по обновлению информации о сервисах:
    ```bash
    devops0@otus-pg:~$ sudo systemctl daemon-reload
    ```
    - Проверим список кластеров:
    ```bash
    devops0@otus-pg:~$ pg_lsclusters
    Ver Cluster  Port Status Owner    Data directory                  Log file
    14  20230302 5434 down   postgres /var/lib/postgresql/14/20230302 /var/log/postgresql/postgresql-14-20230302.log
    14  main     5433 online postgres /var/lib/postgresql/14/main     /var/log/postgresql/postgresql-14-main.log
    15  main     5432 down   postgres /var/lib/postgresql/15/main     /var/log/postgresql/postgresql-15-main.log

    ```
    - Запомним порт (5434).
    - Запустим новый кластер:
    ```bash
    devops0@otus-pg:~$ sudo pg_ctlcluster 14 20230302 start
    ```
2. Заходим:
```bash
devops0@otus-pg:~$ sudo -u postgres -i
postgres@otus-pg:~$ psql -p 5434
psql (15.2 (Debian 15.2-1.pgdg110+1), server 14.7 (Debian 14.7-1.pgdg110+1))
Type "help" for help.

postgres=#
```
3. Создаём новую базу данных:
```bash
postgres=# CREATE DATABASE testdb;
CREATE DATABASE
```
4. Подключаемся к новой базе данных:
```bash
postgres=# \c testdb;
psql (15.2 (Debian 15.2-1.pgdg110+1), server 14.7 (Debian 14.7-1.pgdg110+1))
You are now connected to database "testdb" as user "postgres".
testdb=#
```
5. Создаём схему:
```bash
testdb=# CREATE SCHEMA testnm;
CREATE SCHEMA
```
6. Создаём таблицу:
```bash
testdb=# CREATE TABLE t1(c1 integer);
CREATE TABLE
```
7. Записываем значение в таблицу:
```bash
testdb=# INSERT INTO t1 values(1);
INSERT 0 
```

8. Создаём новую роль:
```bash
testdb=# CREATE role readonly;
CREATE ROLE
```

9. Дадим новой роли право подключаться к базе данных:
```bash
testdb=# GRANT CONNECT ON DATABASE testdb TO readonly;
GRANT
```

10. Дадим новой роли право использовать новую схему testnm:
```bash
testdb=# GRANT USAGE ON SCHEMA testnm TO readonly;
GRANT
```

11. Дадим новой роли право делать выборку из всех таблиц новой схемы:
```bash
testdb=# GRANT SELECT ON ALL TABLES IN SCHEMA testnm TO readonly;
GRANT
```

12. Создадим пользователя с указанием пароля:
```bash
testdb=# CREATE USER testread WITH PASSWORD 'test123';
CREATE ROLE
```

13. Назначим новому пользователю роль readonly:
```bash
testdb=# GRANT readonly TO testread;
GRANT ROLE
```

14. Завершим сеанс пользователя postgres:
```bash
testdb=# \q
```

15. Подключимся под новым пользователем, явно указав сервер, порт и базу данных (потребуется ввести пароль):
```bash
postgres@otus-pg:~$ psql -h localhost -p 5434 -U testread -d testdb
Password:
psql (15.2 (Debian 15.2-1.pgdg110+1), server 14.7 (Debian 14.7-1.pgdg110+1))
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.
```

16. Попытаемся сделать выборку:
```bash
testdb=> select * from t1;
ERROR:  permission denied for table t1
```

17. Нет прав на чтение таблицы t1 у пользователя testread.

18. Права были даны для схемы testnm, а по умолчанию используется схема public.

19. Смотрим список таблиц:
```bash
testdb=> \dt
        List of relations
 Schema | Name | Type  |  Owner
--------+------+-------+----------
 public | t1   | table | postgres
(1 row)
```
20. Подсматриваем шпаргалку. Завершаем сеанс пользователя testread:
```bash
testdb=# \q
```

21. При создании таблицы не была явно указана схема, по этому таблица создалась в схеме по умолчанию public. Нужно пересоздать таблицу в нужной схеме.
22. Подключаемся к БД под пользователем postgres:
```bash
postgres@otus-pg:~$ psql -p 5434 -d testdb
psql (15.2 (Debian 15.2-1.pgdg110+1), server 14.7 (Debian 14.7-1.pgdg110+1))
Type "help" for help.
```

23. Удаляем таблицу:
```bash
testdb=# drop TABLE t1;
DROP TABLE
```

24. Создаём таблицу, явно указав схему:
```bash
testdb=# CREATE TABLE testnm.t1(c1 integer);
CREATE TABLE
```

25. Запишем данные в таблицу, явно указав схему:
```bash
testdb=# INSERT INTO testnm.t1 values(1);
INSERT 0 1
```

26. Перелогинимся в пользователя testread:
```bash
testdb=# \q
postgres@otus-pg:~$ psql -h localhost -p 5434 -U testread -d testdb
Password:
psql (15.2 (Debian 15.2-1.pgdg110+1), server 14.7 (Debian 14.7-1.pgdg110+1))
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.
```

27. Попытаемся сделать выборку:
```bash
testdb=# \q
testdb=> SELECT * FROM testnm.t1;
ERROR:  permission denied for table t1
```
28. Подсматриваем в шпаргалку. Осознаём, что выданные ранее права на SELECT из всех таблиц схему testnm распространяются только на существовавшие на момент запроса таблицы, следовательно, нужно выдать права ещё раз, а так же установить эти права по умолчанию для вновь создаваемых таблиц в схеме для конкретной роли readonly.
29. Перелогиниваемся под учетной записью postgres:
```bash
testdb=> \q
postgres@otus-pg:~$ psql -p 5434 -d testdb
psql (15.2 (Debian 15.2-1.pgdg110+1), server 14.7 (Debian 14.7-1.pgdg110+1))
Type "help" for help.
```

30. Назначим права для существующих таблиц:
```bash
testdb=# GRANT SELECT ON ALL TABLES IN SCHEMA testnm TO readonly;
GRANT
```

31. Назначим права для будущих таблиц:
```bash
testdb=> \q
testdb=# ALTER default privileges in SCHEMA testnm grant SELECT on TABLEs to readonly;
ALTER DEFAULT PRIVILEGES
```
32. Перелогинимся в пользователя testread:
```bash
testdb=# \q
postgres@otus-pg:~$ psql -h localhost -p 5434 -U testread -d testdb
Password:
psql (15.2 (Debian 15.2-1.pgdg110+1), server 14.7 (Debian 14.7-1.pgdg110+1))
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.
```

33. Делаем выборку с указанием конкретной схемы таблицы:
```bash
testdb=> SELECT * FROM testnm.t1;
 c1
----
  1
(1 row)
```
Получилось! Ура!

34. Создаем новую таблицу и записываем в неё данные:
```bash
testdb=> create table t2(c1 integer);
CREATE TABLE
testdb=> insert into t2 values (2);
INSERT 0 1
```
35. Подсмотрел шпаргалку и осознал, что вновь использовалась схема по умолчанию public - у каждого пользователя есть права на работу со схемой public. Выполним рекомендации. Перелогинимся под пользователем postgres:
   ```bash
   testdb=> \q
   postgres@otus-pg:~$ psql -p 5434 -d testdb
   psql (15.2 (Debian 15.2-1.pgdg110+1), server 14.7 (Debian 14.7-1.pgdg110+1))
   Type "help" for help.
   ```
36. Отнимем права на создание таблиц в схеме public у роли public (у всех новых пользователей есть роль public):
   ```bash
   testdb=# revoke CREATE on SCHEMA public FROM public;
   REVOKE
   ```
   Теперь создать таблицу в схеме public смогут только пользователи, ролям которых явно дали права на это.
37. Отнимем все права на базу данных testdb у роли public:
   ```bash
   testdb=# revoke all on DATABASE testdb FROM public;
   REVOKE
   ```
   Доступ к базе testdb остался только у тех пользователей, ролям которых его явно выдали.
   
38. Перелогинимся под пользователем testread и попробуем создать таблицу:
```bash
testdb=# \q
postgres@otus-pg:~$ psql -h localhost -p 5434 -U testread -d testdb
Password:
psql (15.2 (Debian 15.2-1.pgdg110+1), server 14.7 (Debian 14.7-1.pgdg110+1))
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

testdb=> create table t3(c1 integer);
ERROR:  permission denied for schema public
LINE 1: create table t3(c1 integer);
                     ^
```

39. Отсутствует доступ. Права на создание таблиц в схеме public уже отобраны для роли public, а для роли readonly не назначены.

40. Попробуем сделать запись:
```bash
testdb=> insert into t2 values (2);
INSERT 0 1
```
41. Запись удалась, потому что testread владелец таблицы t2 (из документации "Право изменять или удалять объект является неотъемлемым правом владельца объекта, его нельзя лишиться или передать другому." https://postgrespro.ru/docs/postgresql/14/ddl-priv п. 5.7. Права):
```bash
testdb=> \dt
        List of relations
 Schema | Name | Type  |  Owner   
--------+------+-------+----------
 public | t2   | table | testread
(1 row)

```
42. Прошу прощения, если проглядел опечатки или ошибки.