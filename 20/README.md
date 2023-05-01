## Секционирование.

1. Скачаем демо базу и распакуем архив:
```bash
postgres@otus-pg:~$ wget https://edu.postgrespro.com/demo-medium-en.zip
--2023-04-23 23:04:54--  https://edu.postgrespro.com/demo-medium-en.zip
Resolving edu.postgrespro.com (edu.postgrespro.com)... 213.171.56.196
Connecting to edu.postgrespro.com (edu.postgrespro.com)|213.171.56.196|:443... connected.
HTTP request sent, awaiting response... 200 OK
Length: 64544920 (62M) [application/zip]
Saving to: ‘demo-medium-en.zip’
```

2. Распакуем архив:
```bash
postgres@otus-pg:~$ unzip demo-medium-en.zip
Archive:  demo-medium-en.zip
  inflating: demo-medium-en-20170815.sql
```

3. Проверим полученные файлы:
```bash
postgres@otus-pg:~$ ls
13  14a  15  demo-medium-en-20170815.sql  demo-medium-en.zip  sysbench-tpcc
```

4. Создадим новую базу данных:
```bash
postgres@otus-pg:~$ psql
psql (15.2 (Debian 15.2-1.pgdg110+1))
Type "help" for help.

postgres=# create database demo;
CREATE DATABASE
```

5. Импортируем дамп базы:
```bash
postgres=# \c demo
You are now connected to database "demo" as user "postgres".
demo=# \i demo-medium-en-20170815.sql
```

6. Запросим размеры таблиц, чтоб убедиться, что импорт успешно прошел:
```bash
demo=# SELECT nspname || '.' || relname AS "relation",
    pg_size_pretty(pg_total_relation_size(C.oid)) AS "total_size", relkind
  FROM pg_class C
  LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
  WHERE nspname NOT IN ('pg_catalog', 'information_schema')
    AND C.relkind <> 'i'
    AND nspname !~ '^pg_toast'
  ORDER BY pg_total_relation_size(C.oid) DESC;
            relation            | total_size | relkind 
--------------------------------+------------+---------
 bookings.boarding_passes       | 263 MB     | r
 bookings.ticket_flights        | 245 MB     | r
 bookings.tickets               | 134 MB     | r
 bookings.bookings              | 42 MB      | r
 bookings.flights               | 9872 kB    | r
 bookings.seats                 | 144 kB     | r
 bookings.airports_data         | 72 kB      | r
 bookings.aircrafts_data        | 32 kB      | r
 bookings.flights_flight_id_seq | 8192 bytes | S
 bookings.aircrafts             | 0 bytes    | v
 bookings.flights_v             | 0 bytes    | v
 bookings.airports              | 0 bytes    | v
 bookings.routes                | 0 bytes    | v
(13 rows)
```
7. Видим, что в базе есть представления. Проверим, в каких представлениях используется наша таблица специальным запросом (найден в интернете):
```bash
demo=# select u.view_schema as schema_name,
       u.view_name,
       u.table_schema as referenced_table_schema,
       u.table_name as referenced_table_name 
from information_schema.view_table_usage u
join information_schema.views v 
     on u.view_schema = v.table_schema
     and u.view_name = v.table_name
where u.table_schema not in ('information_schema', 'pg_catalog') and u.table_name='flights'
order by u.view_schema,                                                                    
         u.view_name;
 schema_name | view_name | referenced_table_schema | referenced_table_name 
-------------+-----------+-------------------------+-----------------------
 bookings    | flights_v | bookings                | flights
 bookings    | routes    | bookings                | flights
(2 rows)
```
Таблица используется в преставлениях flights_v и routes, следовательно, нужно пересоздавать и их (представления).

8. Получим дампы структур представлений ([flights_v.sql](./flights_v.sql), [routes.sql](./routes.sql)):
```bash
postgres@otus-pg:~$ pg_dump -st flights_v demo > flights_v.sql
postgres@otus-pg:~$ pg_dump -st routes demo > routes.sql
```

9. Получим структуру таблицы flights, которую будем секционировать:
```bash
demo=# \d flights
                                              Table "bookings.flights"
       Column        |           Type           | Collation | Nullable |                  Default
---------------------+--------------------------+-----------+----------+--------------------------------------------
 flight_id           | integer                  |           | not null | nextval('flights_flight_id_seq'::regclass)
 flight_no           | character(6)             |           | not null |
 scheduled_departure | timestamp with time zone |           | not null |
 scheduled_arrival   | timestamp with time zone |           | not null |
 departure_airport   | character(3)             |           | not null |
 arrival_airport     | character(3)             |           | not null |
 status              | character varying(20)    |           | not null |
 aircraft_code       | character(3)             |           | not null |
 actual_departure    | timestamp with time zone |           |          |
 actual_arrival      | timestamp with time zone |           |          |
Indexes:
    "flights_pkey" PRIMARY KEY, btree (flight_id)
    "flights_flight_no_scheduled_departure_key" UNIQUE CONSTRAINT, btree (flight_no, scheduled_departure)
Check constraints:
    "flights_check" CHECK (scheduled_arrival > scheduled_departure)
    "flights_check1" CHECK (actual_arrival IS NULL OR actual_departure IS NOT NULL AND actual_arrival IS NOT NULL AND actual_arrival > actual_departure)
    "flights_status_check" CHECK (status::text = ANY (ARRAY['On Time'::character varying::text, 'Delayed'::character varying::text, 'Departed'::character varying::text, 'Arrived'::character varying::text, 'Scheduled'::character varying::text, 'Cancelled'::character varying::text]))
Foreign-key constraints:
    "flights_aircraft_code_fkey" FOREIGN KEY (aircraft_code) REFERENCES aircrafts_data(aircraft_code)
    "flights_arrival_airport_fkey" FOREIGN KEY (arrival_airport) REFERENCES airports_data(airport_code)
    "flights_departure_airport_fkey" FOREIGN KEY (departure_airport) REFERENCES airports_data(airport_code)
Referenced by:
    TABLE "ticket_flights" CONSTRAINT "ticket_flights_flight_id_fkey" FOREIGN KEY (flight_id) REFERENCES flights(flight_id)
```

Видим, что в таблице есть первичный ключ `flight_id`, а так же 3 внешних ключа `flights_aircraft_code_fkey`, `flights_arrival_airport_fkey`, `flights_departure_airport_fkey`.
А ещё ключ `ticket_flights_flight_id_fkey` таблицы `ticket_flights` ссылается на `flight_id` нашей таблицы.

8. Секционирование будем делать через создание дополнительной таблицы с временним названием. Для того, чтоб корректно создать все существующие индексы секционируемой таблицы,
снимем дамп её структуры ([demo_flights.sql](./demo_flights.sql)):
```bash
postgres@otus-pg:~$ pg_dump -st flights demo > demo_flights.sql
```

9. Создадим таблицу на основе дампа с секционированием по полю со временем вылета scheduled_departure, сразу создадим партиции на 8 месяцев:
```bash
demo=# CREATE TABLE bookings.flights_range (
    flight_id integer NOT NULL,
    flight_no character(6) NOT NULL,
    scheduled_departure timestamp with time zone NOT NULL,
    scheduled_arrival timestamp with time zone NOT NULL,
    departure_airport character(3) NOT NULL,
    arrival_airport character(3) NOT NULL,
    status character varying(20) NOT NULL,
    aircraft_code character(3) NOT NULL,
    actual_departure timestamp with time zone,
    actual_arrival timestamp with time zone,
    CONSTRAINT flights_check CHECK ((scheduled_arrival > scheduled_departure)),
    CONSTRAINT flights_check1 CHECK (((actual_arrival IS NULL) OR ((actual_departure IS NOT NULL) AND (actual_arrival IS NOT NULL) AND (actual_arrival > actual_departure)))),
    CONSTRAINT flights_status_check CHECK (((status)::text = ANY (ARRAY[('On Time'::character varying)::text, ('Delayed'::character varying)::text, ('Departed'::character varying)::text, ('Arrived'::character varying)::text, ('Scheduled'::character varying)::text, ('Cancelled'::character varying)::text])))
)partition by range (scheduled_departure);
CREATE TABLE
demo=# create table flights_2017_05 partition of flights_range for values from ('2017-05-01') to ('2017-06-01');
CREATE TABLE
demo=# create table flights_2017_06 partition of flights_range for values from ('2017-06-01') to ('2017-07-01');
CREATE TABLE
demo=# create table flights_2017_07 partition of flights_range for values from ('2017-07-01') to ('2017-08-01');
CREATE TABLE
demo=# create table flights_2017_08 partition of flights_range for values from ('2017-08-01') to ('2017-09-01');
CREATE TABLE
demo=# create table flights_2017_09 partition of flights_range for values from ('2017-09-01') to ('2017-10-01');
CREATE TABLE
demo=# create table flights_2017_10 partition of flights_range for values from ('2017-10-01') to ('2017-11-01');
CREATE TABLE
demo=# create table flights_2017_11 partition of flights_range for values from ('2017-11-01') to ('2017-12-01');
CREATE TABLE
demo=# create table flights_2017_12 partition of flights_range for values from ('2017-12-01') to ('2018-01-01');
CREATE TABLE
```

10. Заполним секционированную таблицу данными из таблицы-донора:
```bash
demo=# insert into flights_range select * from flights;
INSERT 0 65664
```

11. Проверим, что получилось:
```bash
demo=# \d+ flights_range;
                                              Partitioned table "bookings.flights_range"
       Column        |           Type           | Collation | Nullable | Default | Storage  | Compression | Stats target | Description
---------------------+--------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 flight_id           | integer                  |           | not null |         | plain    |             |              |
 flight_no           | character(6)             |           | not null |         | extended |             |              |
 scheduled_departure | timestamp with time zone |           | not null |         | plain    |             |              |
 scheduled_arrival   | timestamp with time zone |           | not null |         | plain    |             |              |
 departure_airport   | character(3)             |           | not null |         | extended |             |              |
 arrival_airport     | character(3)             |           | not null |         | extended |             |              |
 status              | character varying(20)    |           | not null |         | extended |             |              |
 aircraft_code       | character(3)             |           | not null |         | extended |             |              |
 actual_departure    | timestamp with time zone |           |          |         | plain    |             |              |
 actual_arrival      | timestamp with time zone |           |          |         | plain    |             |              |
Partition key: RANGE (scheduled_departure)
Check constraints:
    "flights_check" CHECK (scheduled_arrival > scheduled_departure)
    "flights_check1" CHECK (actual_arrival IS NULL OR actual_departure IS NOT NULL AND actual_arrival IS NOT NULL AND actual_arrival > actual_departure)
    "flights_status_check" CHECK (status::text = ANY (ARRAY['On Time'::character varying::text, 'Delayed'::character varying::text, 'Departed'::character varying::text, 'Arrived'::character varying::text, 'Scheduled'::character varying::text, 'Cancelled'::character varying::text]))
Partitions: flights_2017_05 FOR VALUES FROM ('2017-05-01 00:00:00+05') TO ('2017-06-01 00:00:00+05'),
            flights_2017_06 FOR VALUES FROM ('2017-06-01 00:00:00+05') TO ('2017-07-01 00:00:00+05'),
            flights_2017_07 FOR VALUES FROM ('2017-07-01 00:00:00+05') TO ('2017-08-01 00:00:00+05'),
            flights_2017_08 FOR VALUES FROM ('2017-08-01 00:00:00+05') TO ('2017-09-01 00:00:00+05'),
            flights_2017_09 FOR VALUES FROM ('2017-09-01 00:00:00+05') TO ('2017-10-01 00:00:00+05'),
            flights_2017_10 FOR VALUES FROM ('2017-10-01 00:00:00+05') TO ('2017-11-01 00:00:00+05'),
            flights_2017_11 FOR VALUES FROM ('2017-11-01 00:00:00+05') TO ('2017-12-01 00:00:00+05'),
            flights_2017_12 FOR VALUES FROM ('2017-12-01 00:00:00+05') TO ('2018-01-01 00:00:00+05')

```

12. Удалим представления:
```bash
demo=# drop view flights_v;
DROP VIEW
demo=# drop view routes;
DROP VIEW
```

13. Удалим внешний ключ ticket_flights_flight_id_fkey из таблицы ticket_flights, иначе не получится удалить таблицу-донора:
```bash
demo=# ALTER TABLE ONLY bookings.ticket_flights DROP constraint ticket_flights_flight_id_fkey;
ALTER TABLE
```

14. Переименуем таблицы:
```bash
demo=# alter table flights rename to flights_not_range;
ALTER TABLE
demo=# alter table flights_range rename to flights;
ALTER TABLE
```

15. Удалим таблицу-донора:
```bash
demo=# drop table flights_not_range;
DROP TABLE
```

16. Создадим представление flights_v:
```bash
demo=# CREATE VIEW bookings.flights_v AS
 SELECT f.flight_id,
    f.flight_no,
    f.scheduled_departure,
    timezone(dep.timezone, f.scheduled_departure) AS scheduled_departure_local,
    f.scheduled_arrival,
    timezone(arr.timezone, f.scheduled_arrival) AS scheduled_arrival_local,
    (f.scheduled_arrival - f.scheduled_departure) AS scheduled_duration,
    f.departure_airport,
    dep.airport_name AS departure_airport_name,
    dep.city AS departure_city,
    f.arrival_airport,
    arr.airport_name AS arrival_airport_name,
    arr.city AS arrival_city,
    f.status,
    f.aircraft_code,
    f.actual_departure,
    timezone(dep.timezone, f.actual_departure) AS actual_departure_local,
    f.actual_arrival,
    timezone(arr.timezone, f.actual_arrival) AS actual_arrival_local,
    (f.actual_arrival - f.actual_departure) AS actual_duration
   FROM bookings.flights f,
    bookings.airports dep,
    bookings.airports arr
  WHERE ((f.departure_airport = dep.airport_code) AND (f.arrival_airport = arr.airport_code));
CREATE VIEW

demo=# ALTER TABLE bookings.flights_v OWNER TO postgres;
ALTER TABLE
```

17. Создадим представление routes:
```bash
demo=# CREATE VIEW bookings.routes AS
WITH f3 AS (
    SELECT f2.flight_no,
           f2.departure_airport,
           f2.arrival_airport,
           f2.aircraft_code,
           f2.duration,
           array_agg(f2.days_of_week) AS days_of_week
    FROM ( SELECT f1.flight_no,
                  f1.departure_airport,
                  f1.arrival_airport,
                  f1.aircraft_code,
                  f1.duration,
                  f1.days_of_week
           FROM ( SELECT flights.flight_no,
                         flights.departure_airport,
                         flights.arrival_airport,
                         flights.aircraft_code,
                         (flights.scheduled_arrival - flights.scheduled_departure) AS duration,
                         (to_char(flights.scheduled_departure, 'ID'::text))::integer AS days_of_week
                  FROM bookings.flights) f1
           GROUP BY f1.flight_no, f1.departure_airport, f1.arrival_airport, f1.aircraft_code, f1.duration, f1.days_of_week
           ORDER BY f1.flight_no, f1.departure_airport, f1.arrival_airport, f1.aircraft_code, f1.duration, f1.days_of_week) f2
    GROUP BY f2.flight_no, f2.departure_airport, f2.arrival_airport, f2.aircraft_code, f2.duration
)
SELECT f3.flight_no,
       f3.departure_airport,
       dep.airport_name AS departure_airport_name,
       dep.city AS departure_city,
       f3.arrival_airport,
       arr.airport_name AS arrival_airport_name,
       arr.city AS arrival_city,
       f3.aircraft_code,
       f3.duration,
       f3.days_of_week
FROM f3,
     bookings.airports dep,
     bookings.airports arr
WHERE ((f3.departure_airport = dep.airport_code) AND (f3.arrival_airport = arr.airport_code));
CREATE VIEW

demo=# ALTER TABLE bookings.routes OWNER TO postgres;
ALTER TABLE
```

18. Попробуем вернуть ключ новой таблице:
```bash
demo=# ALTER TABLE ONLY bookings.flights
    ADD CONSTRAINT flights_pkey PRIMARY KEY (flight_id);
ERROR:  unique constraint on partitioned table must include all partitioning columns
DETAIL:  PRIMARY KEY constraint on table "flights" lacks column "scheduled_departure" which is part of the partition key.

```
19. Вернуть ссылку на из таблицы `ticket_flights` на `flights` не удастся, потому что в новой таблице нет первичного ключа, первичный ключ должен учавствовать в секционировании:
```bash
demo=# ALTER TABLE ONLY bookings.ticket_flights ADD constraint ticket_flights_flight_id_fkey FOREIGN KEY (flight_id) REFERENCES flights(flight_id);
ERROR:  there is no unique constraint matching given keys for referenced table "flights"
```

20. Вернём внешние ключи:
```bash
demo=# ALTER TABLE bookings.flights
    ADD CONSTRAINT flights_aircraft_code_fkey FOREIGN KEY (aircraft_code) REFERENCES bookings.aircrafts_data(aircraft_code);
ALTER TABLE
demo=# ALTER TABLE bookings.flights
    ADD CONSTRAINT flights_arrival_airport_fkey FOREIGN KEY (arrival_airport) REFERENCES bookings.airports_data(airport_code);
ALTER TABLE
demo=# ALTER TABLE bookings.flights
    ADD CONSTRAINT flights_departure_airport_fkey FOREIGN KEY (departure_airport) REFERENCES bookings.airports_data(airport_code);
ALTER TABLE
```

21. Удалим таблицу-донора:
```bash
demo=# drop table flights_not_range;
DROP TABLE
```

Вывод: мы секционировали таблицу по времени вылета. Размер секции - записи за месяц. При такой схеме секционирования придется
по расписанию выполнять задачу создания дополнительных партиций на следующий месяц вперёд.
Мы потеряли первичный ключ, а вместе с ним связь с таблицей `ticket_flights`.
