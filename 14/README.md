## Виды и устройство репликации в PostgreSQL. Практика применения.

1. Создадим 3 виртуальные машины на ЯО, ОС - Ubuntu 22.04:

- 1ВМ - 158.160.9.198
- 2ВМ - 158.160.27.164
- 3ВМ - 158.160.16.16

2. На каждой из ВМ выполним команду обновления пакетов и усановки PostgreSQL 14:

```bash
sudo apt update && sudo apt dist-upgrade -y
sudo apt install postgresql-14 -y
```

3. На каждой из ВМ создадим базу test, в ней таблицы test, test2:

```bash
sudo -u postgres psql
psql (14.7 (Ubuntu 14.7-0ubuntu0.22.04.1))
Type "help" for help.

postgres=#
postgres=# create database test;
CREATE DATABASE
postgres=# \c test;
You are now connected to database "test" as user "postgres".
```

```bash
postgres=# create database test;
CREATE DATABASE
```

```bash
postgres=# \c test;
You are now connected to database "test" as user "postgres".
```

```bash
test=# CREATE TABLE test(i int);
CREATE TABLE
test=# CREATE TABLE test2(i int);
CREATE TABLE
test=#
```

4. 2ВМ и 3ВМ разрешим PostgreSQL принимать запросы на всех интерфейсах, для этого поправим файл **
   /etc/postgresql/14/main/postgresql.conf**:

```bash
#listen_addresses = 'localhost'         # what IP address(es) to listen on;
```

заменим на

```bash
listen_addresses = '*'         # what IP address(es) to listen on;
```

5. На 1ВМ настроим доступ для подключения с 2ВМ и 3ВМ. Для этого добавим строки в файл **
   /etc/postgresql/14/main/pg_hba.conf**:

```bash
# Доступ с 2ВМ
host    all             postgres        158.160.27.164/32        scram-sha-256
# Доступ с 3ВМ
host    all             postgres        158.160.16.16/32         scram-sha-256
```

6. На 1ВМ установим пароль для пользователя, от имени которого будет происходить публикации реплик, в нашем случае это
   postgres, пароль 02042023:

```bash
sudo -u postgres psql
postgres=# \password
```

7. На 1ВМ установим уровень записей WAL = logical:

```bash
sudo -u postgres psql
postgres=# ALTER SYSTEM SET wal_level = logical;
postgres=# \q
```

8. На 1ВМ перезагрузим кластер:

```bash
sudo pg_ctlcluster 14 main restart
```

9. На 1ВМ создадим публикацию таблицы test:

```bash
sudo -u postgres psql
postgres=# \с test;
test=# CREATE PUBLICATION test_pub FOR TABLE test;
CREATE PUBLICATION
test=# \dRp+
                            Publication test_pub
  Owner   | All tables | Inserts | Updates | Deletes | Truncates | Via root
----------+------------+---------+---------+---------+-----------+----------
 postgres | f          | t       | t       | t       | t         | f
Tables:
    "public.test"

test=#
```

10. Аналогично, на 2ВМ настроим доступ для подключения с 1ВМ и 3ВМ. Для этого добавим строки в файл **
    /etc/postgresql/14/main/pg_hba.conf**:

```bash
# Доступ с 1ВМ
host    all             postgres        158.160.9.198/32        scram-sha-256
# Доступ с 3ВМ
host    all             postgres        158.160.16.16/32         scram-sha-256
```

11. На 2ВМ установим пароль для пользователя, от имени которого будет происходить публикации реплик, в нашем случае это
    postgres, пароль 02042023:

```bash
sudo -u postgres psql
postgres=# \password
```

12. На 2ВМ установим уровень записей WAL = logical:

```bash
sudo -u postgres psql
postgres=# ALTER SYSTEM SET wal_level = logical;
postgres=# \q
```

13. На 2ВМ перезагрузим кластер:

```bash
sudo pg_ctlcluster 14 main restart
```

14. На 2ВМ создадим публикацию таблицы test2:

```bash
sudo -u postgres psql
postgres=# \с test;
test=# CREATE PUBLICATION test_pub FOR TABLE test2;
CREATE PUBLICATION
test=# \dRp+
                            Publication test_pub
  Owner   | All tables | Inserts | Updates | Deletes | Truncates | Via root
----------+------------+---------+---------+---------+-----------+----------
 postgres | f          | t       | t       | t       | t         | f
Tables:
    "public.test2"

test=#
```

15. Подпишемся с 2ВМ на публикацию 1ВМ:

```bash
test=# CREATE SUBSCRIPTION test_sub
CONNECTION 'host=158.160.9.198 port=5432 user=postgres password=02042023 dbname=test'
PUBLICATION test_pub WITH (copy_data = false);
NOTICE:  created replication slot "test_sub" on publisher
CREATE SUBSCRIPTION
```

16. Выполним проверочные запросы на 2ВМ:

```bash
test=# select * from test;
 i
---
(0 rows)
test=# select * from test2;
 i
---
(0 rows)
```

Таблицы пусты.

17. Проверим список подписок на 2ВМ:

```bash
test=# \dRs
            List of subscriptions
   Name   |  Owner   | Enabled | Publication
----------+----------+---------+-------------
 test_sub | postgres | t       | {test_pub}
(1 row)
```

18. Вернёмся на 1ВМ, создадим подписку на публикацию 2ВМ:

```bash
test=# CREATE SUBSCRIPTION test_sub
CONNECTION 'host=158.160.27.164 port=5432 user=postgres password=02042023 dbname=test'
PUBLICATION test_pub WITH (copy_data = false);
NOTICE:  created replication slot "test_sub" on publisher
CREATE SUBSCRIPTION
```

19. Выполним проверочные запросы на 1ВМ:

```bash
test=# select * from test;
 i
---
(0 rows)
test=# select * from test2;
 i
---
(0 rows)
```

Таблицы тоже пусты.

20. Проверим список подписок на 1ВМ:

```bash
test=# \dRs
            List of subscriptions
   Name   |  Owner   | Enabled | Publication
----------+----------+---------+-------------
 test_sub | postgres | t       | {test_pub}
(1 row)
```

21. Добавим записи в талицу test на 1ВМ:

```bash
test=# INSERT INTO test(i) values(1);
INSERT 0 1
test=# INSERT INTO test(i) values(2);
INSERT 0 1
test=# INSERT INTO test(i) values(3);
INSERT 0 1
test=#
```

22. Сделаем выборку из таблицы test на 1ВМ:

```bash
test=# select * from test;
 i
---
 1
 2
 3
(3 rows)
```

23. Сделаем выборку из таблицы test на 2ВМ:

```bash
test=# select * from test;
 i
---
 1
 2
 3
(3 rows)
```

24. Добавим записи в талицу test2 на 2ВМ:

```bash
test=# INSERT INTO test2(i) values(4);
INSERT 0 1
test=# INSERT INTO test2(i) values(5);
INSERT 0 1
test=# INSERT INTO test2(i) values(6);
INSERT 0 1
```

25. Сделаем выборку из таблицы test2 на 1ВМ:

```bash
test=# select * from test2;
 i
---
 4
 5
 6
(3 rows)
```

26. На 3ВМ создадим 2 подписки - на 1ВМ и 2ВМ, укажем, что нужно забрать существующие данные:

```bash
test=# CREATE SUBSCRIPTION test_sub_vm1_test
CONNECTION 'host=158.160.9.198 port=5432 user=postgres password=02042023 dbname=test'
PUBLICATION test_pub WITH (copy_data = true);

test=# CREATE SUBSCRIPTION test_sub_vm2_test2
CONNECTION 'host=158.160.27.164 port=5432 user=postgres password=02042023 dbname=test'
PUBLICATION test_pub WITH (copy_data = true);
```

27. Проверим список подписок на 3ВМ:

```bash
test=# \dRs
                 List of subscriptions
        Name        |  Owner   | Enabled | Publication
--------------------+----------+---------+-------------
 test_sub_vm1_test  | postgres | t       | {test_pub}
 test_sub_vm2_test2 | postgres | t       | {test_pub}
(2 rows)
```

28. Сделаем тестовые выборки из таблиц test и test2 на 3ВМ:

```bash
test=# select * from test;
 i
---
 1
 2
 3
(3 rows)

test=# select * from test2;
 i
---
 4
 5
 6
(3 rows)
```
Данные реплицировались.

29. Для проверки вернемся на 1ВМ и добавим запись в таблицу test:

```bash
test=# INSERT INTO test(i) values(111);
INSERT 0 1
test=#
```

30. На 2ВМ и добавим запись в таблицу test2:

```bash
test=# INSERT INTO test2(i) values(222);
INSERT 0 1
test=#
```

31. Сделаем тестовые выборки из таблиц test и test2 на 3ВМ:

```bash
test=# select * from test;
 i
---
 1
 2
 3
 111
(4 rows)

test=# select * from test2;
 i
---
 4
 5
 6
 222
(4 rows)
```
Новые строки тоже реплицировались. С этими же запросами получим точно такой же результат на 1ВМ и 2ВМ.

Мы настроили взаимную репликацию таблиц для 1ВМ и 2ВМ, а 3ВМ играет роль общей копии первых 2-х баз. 
1ВМ может отдавать через публикацию свои данные из таблицы test, и получает данные для своей таблицы для чтения test2 от публикации на 2ВМ.
В ответ, 2ВМ получает данные для своей таблицы для чтения test от публикации на 1ВМ, и отдает свои записи из таблицы test2 через публикацию.
3ВМ только получает данные через подписки на публикации 1ВМ и 2ВМ. На 3ВМ можно производить чтение обеих таблиц и настраивать бэкапирование БД
без ущерба для 1ВМ и 2ВМ.
