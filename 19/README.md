## Сбор и использование статистики.

### Вариант 1

Использовалась ВМ на внешнем хостинге Debian 11, PostgreSQL 15.

1. Создадим тестовую таблицу и заполним её тестовыми данными.
```bash
postgres=# create table test as
select generate_series as id
        , generate_series::text || (random() * 10)::text as col2
    , (array['Yes', 'No', 'Maybe'])[floor(random() * 3 + 1)] as is_okay
from generate_series(1, 50000);
SELECT 50000
```
Выясним, как работает выборка без индексов:
```bash
postgres=# explain
select id from test where id = 1;
                      QUERY PLAN
-------------------------------------------------------
 Seq Scan on test  (cost=0.00..1007.00 rows=1 width=4)
   Filter: (id = 1)
(2 rows)
```
Сканирование происходит по всем данным.

2. Создадим индекс:
```bash
postgres=# create index idx_test_id on test(id);
CREATE INDEX 
```
Выясним, как работает выборка c индексом:
```bash
postgres=# explain
select id from test where id = 1;
                                 QUERY PLAN
-----------------------------------------------------------------------------
 Index Only Scan using idx_test_id on test  (cost=0.29..4.31 rows=1 width=4)
   Index Cond: (id = 1)
(2 rows)
```
Видим, что при выборке используется индекс, значение cost уменьшилось.

3. Для демонстрации работы полнотекстового индекса создадим другую тестовую таблицу и заполним её данными:
```bash
postgres=# insert into orders(id, user_id, order_date, status, some_text)
select generate_series, (random() * 70), date'2019-01-01' + (random() * 300)::int as order_date
        , (array['returned', 'completed', 'placed', 'shipped'])[(random() * 4)::int]
        , concat_ws(' ', (array['go', 'space', 'sun', 'London'])[(random() * 5)::int]
            , (array['the', 'capital', 'of', 'Great', 'Britain'])[(random() * 6)::int]
            , (array['some', 'another', 'example', 'with', 'words'])[(random() * 6)::int]
            )
from generate_series(1, 500000);
INSERT 0 500000
```

Посмотрим, как работает выборка к этой таблице без индексов с использованием лексем:
```bash
postgres=# explain select some_text, to_tsvector(some_text) @@ to_tsquery('britains')
from orders;
                                   QUERY PLAN
---------------------------------------------------------------------------------
 Gather  (cost=1000.00..394177.41 rows=1222735 width=15)
   Workers Planned: 2
   ->  Parallel Seq Scan on orders  (cost=0.00..270903.91 rows=509473 width=15)
 JIT:
   Functions: 2
   Options: Inlining false, Optimization false, Expressions true, Deforming true
(6 rows)
```

Для использования полнотекстового индекса добавим столбец типа tsvector, в который запишем значения ф-ии to_tsvector:
```bash
postgres=# alter table orders add column some_text_lexeme tsvector;
ALTER TABLE
postgres=# update orders
set some_text_lexeme = to_tsvector(some_text);
UPDATE 500000
```

На поле some_text_lexeme создадим USING GIN индекс:
```bash
postgres=# CREATE INDEX search_index_ord ON orders USING GIN (some_text_lexeme);
CREATE INDEX
```

Посмотрим план запроса:
```bash
postgres=# explain
select *
from orders
where some_text_lexeme @@ to_tsquery('britains');
                                        QUERY PLAN
-------------------------------------------------------------------------------------------
 Gather  (cost=1793.58..29459.18 rows=85333 width=63)
   Workers Planned: 2
   ->  Parallel Bitmap Heap Scan on orders  (cost=793.58..19925.88 rows=35555 width=63)
         Recheck Cond: (some_text_lexeme @@ to_tsquery('britains'::text))
         ->  Bitmap Index Scan on search_index_ord  (cost=0.00..772.25 rows=85333 width=0)
               Index Cond: (some_text_lexeme @@ to_tsquery('britains'::text))
(6 rows)
```
Оптимизатор запросов использует созданный индекс: `Bitmap Index Scan on search_index_ord  (cost=0.00..772.25 rows=85333 width=0)`

4. Для реализации индекса на часть таблицы вернемся к таблице test и создадим такой индекс:
```bash
postgres=# drop table if exists test;
DROP TABLE

postgres=# create table test as
select generate_series as id
        , generate_series::text || (random() * 10)::text as col2
    , (array['Yes', 'No', 'Maybe'])[floor(random() * 3 + 1)] as is_okay
from generate_series(1, 50000);
SELECT 50000

postgres=# create index idx_test_id_100 on test(id) where id < 100;
CREATE INDEX
```

Посмотрим план запроса, который будет использовать такой индекс:
```bash
postgres=# explain                                                
select * from test where id < 50;
                                  QUERY PLAN                                   
-------------------------------------------------------------------------------
 Index Scan using idx_test_id_100 on test  (cost=0.14..13.04 rows=51 width=31)
   Index Cond: (id < 50)
(2 rows)
```
При таком условии используется индекс: `Scan using idx_test_id_100 on test  (cost=0.14..13.04 rows=51 width=31)`

Посмотрим план запроса, который будет использовать такой индекс при несоответствующем условии:
```bash
postgres=# explain                                                
select * from test where id > 500;
                         QUERY PLAN                         
------------------------------------------------------------
 Seq Scan on test  (cost=0.00..1008.00 rows=49480 width=31)
   Filter: (id > 500)
(2 rows)
```
Таблица сканируется полностью.

Для индекса на поле с функцией создадим полнотекстовый индекс на поле some_text:
```bash
postgres=# CREATE INDEX search_index_some_text ON orders USING GIN (to_tsvector('english', some_text));
CREATE INDEX
```

Посмотрим план запроса:
```bash
postgres=# explain select some_text
from orders
where to_tsvector('english', some_text) @@ to_tsquery('britains')
;
                                                QUERY PLAN                                                
----------------------------------------------------------------------------------------------------------
 Gather  (cost=1773.18..37664.18 rows=83217 width=14)
   Workers Planned: 2
   ->  Parallel Bitmap Heap Scan on orders  (cost=773.18..28342.48 rows=34674 width=14)
         Recheck Cond: (to_tsvector('english'::regconfig, some_text) @@ to_tsquery('britains'::text))
         ->  Bitmap Index Scan on search_index_some_text  (cost=0.00..752.38 rows=83217 width=0)
               Index Cond: (to_tsvector('english'::regconfig, some_text) @@ to_tsquery('britains'::text))
(6 rows)
```
Оптимизатор запросов использует созданный индекс: `Bitmap Index Scan on search_index_some_text  (cost=0.00..752.38 rows=83217 width=0)`

5. Для реализации индекса на несколько полей вернемся к таблице test:
```bash
postgres=# drop table if exists test;
DROP TABLE
postgres=# create table test as
select generate_series as id
        , generate_series::text || (random() * 10)::text as col2
    , (array['Yes', 'No', 'Maybe'])[floor(random() * 3 + 1)] as is_okay
from generate_series(1, 50000);
SELECT 50000
```
Посмотрим план запросов с фильтром по двум полям:
```bash
postgres=# explain
select * from test where id = 1 and is_okay = 'Yes';
                       QUERY PLAN                       
--------------------------------------------------------
 Seq Scan on test  (cost=0.00..1132.00 rows=1 width=31)
   Filter: ((id = 1) AND (is_okay = 'Yes'::text))
(2 rows)

postgres=# explain
select * from test where id = 1;
                       QUERY PLAN                       
--------------------------------------------------------
 Seq Scan on test  (cost=0.00..1007.00 rows=1 width=31)
   Filter: (id = 1)
(2 rows)

postgres=# explain
select * from test where is_okay = 'Yes';
                       QUERY PLAN                       
--------------------------------------------------------
 Seq Scan on test  (cost=0.00..1007.00 rows=1 width=31)
   Filter: (is_okay = 'Yes'::text)
(2 rows)
```
Добавим индекс на два поля:
```bash
postgres=# create index idx_test_id_is_okay on test(id, is_okay);
CREATE INDEX
```
Выясним, как используются индексы с разными условиями:
```bash
postgres=# explain
select * from test where id = 1 and is_okay = 'Yes';
                                   QUERY PLAN                                    
---------------------------------------------------------------------------------
 Index Scan using idx_test_id_is_okay on test  (cost=0.29..8.31 rows=1 width=31)
   Index Cond: ((id = 1) AND (is_okay = 'Yes'::text))
(2 rows)
```
При отборе по двум полям оптимизатор использует созданный индекс: `Scan using idx_test_id_is_okay on test  (cost=0.29..8.31 rows=1 width=31)`

```bash
postgres=# explain
select * from test where id = 1;
                                   QUERY PLAN                                    
---------------------------------------------------------------------------------
 Index Scan using idx_test_id_is_okay on test  (cost=0.29..8.31 rows=1 width=31)
   Index Cond: (id = 1)
(2 rows)
```
При отборе по первому полю из индекса оптимизатор использует созданный индекс: `Scan using idx_test_id_is_okay on test  (cost=0.29..8.31 rows=1 width=31)`

```bash
postgres=# explain
select * from test where is_okay = 'Yes';
                         QUERY PLAN                         
------------------------------------------------------------
 Seq Scan on test  (cost=0.00..1007.00 rows=16633 width=31)
   Filter: (is_okay = 'Yes'::text)
(2 rows)
```
При отборе по второму полю из индекса оптимизатор НЕ использует созданный индекс, сканирует всю таблицу (проверено на PostgerSQL 15, 14), хотя на лекции было сказано,
что с версии 14 при условии отбора по второму полю индекса должен использоваться индекс.

Пункты 5 и 6 выполнены в процессе выполнения задания.

### Вариант 2

1. Создадим таблицы для работы с соединениями bus - маршруты, model_bus - модели автобусов:
```bash
postgres=# create table bus (id serial,route text,id_model int);
create table model_bus (id serial,name text);;
insert into bus values (1,'Москва-Болшево',1),(2,'Москва-Пушкино',1),(3,'Москва-Ярославль',2),(4,'Москва-Кострома',2),(5,'Москва-Волгорад',3),
                       (6,'Москва-Иваново',null),(7,'Москва-Саратов',null),(8,'Москва-Воронеж',null);
insert into model_bus values(1,'ПАЗ'),(2,'ЛИАЗ'),(3,'MAN'),(4,'МАЗ'),(5,'НЕФАЗ'),(6,'ЗиС'),(7,'Икарус');
CREATE TABLE
CREATE TABLE
INSERT 0 8
INSERT 0 7
```

Выполним запрос с прямым соединением двух таблиц по идентификатору модели автобуса:
```bash
postgres=# explain
select *
from bus b
join model_bus mb
    on b.id_model=mb.id;
                               QUERY PLAN
-------------------------------------------------------------------------
 Hash Join  (cost=1.16..2.32 rows=5 width=49)
   Hash Cond: (b.id_model = mb.id)
   ->  Seq Scan on bus b  (cost=0.00..1.08 rows=8 width=37)
   ->  Hash  (cost=1.07..1.07 rows=7 width=12)
         ->  Seq Scan on model_bus mb  (cost=0.00..1.07 rows=7 width=12)
(5 rows)

postgres=# select *
from bus b
join model_bus mb
    on b.id_model=mb.id;
 id |      route       | id_model | id | name 
----+------------------+----------+----+------
  1 | Москва-Болшево   |        1 |  1 | ПАЗ
  2 | Москва-Пушкино   |        1 |  1 | ПАЗ
  3 | Москва-Ярославль |        2 |  2 | ЛИАЗ
  4 | Москва-Кострома  |        2 |  2 | ЛИАЗ
  5 | Москва-Волгорад  |        3 |  3 | MAN
(5 rows)
```

2. Выполним запрос сначала с левосторонним, а затем с правосторонним соединением двух таблиц по идентификатору модели автобуса:
```bash
postgres=# select *
from bus b
left join model_bus mb
    on b.id_model=mb.id;
 id |      route       | id_model | id | name
----+------------------+----------+----+------
  1 | Москва-Болшево   |        1 |  1 | ПАЗ
  2 | Москва-Пушкино   |        1 |  1 | ПАЗ
  3 | Москва-Ярославль |        2 |  2 | ЛИАЗ
  4 | Москва-Кострома  |        2 |  2 | ЛИАЗ
  5 | Москва-Волгорад  |        3 |  3 | MAN
  6 | Москва-Иваново   |          |    |
  7 | Москва-Саратов   |          |    |
  8 | Москва-Воронеж   |          |    |
(8 rows)

postgres=# select *
from bus b
right join model_bus mb
    on b.id_model=mb.id;
 id |      route       | id_model | id |  name
----+------------------+----------+----+--------
  1 | Москва-Болшево   |        1 |  1 | ПАЗ
  2 | Москва-Пушкино   |        1 |  1 | ПАЗ
  3 | Москва-Ярославль |        2 |  2 | ЛИАЗ
  4 | Москва-Кострома  |        2 |  2 | ЛИАЗ
  5 | Москва-Волгорад  |        3 |  3 | MAN
    |                  |          |  5 | НЕФАЗ
    |                  |          |  6 | ЗиС
    |                  |          |  4 | МАЗ
    |                  |          |  7 | Икарус
(9 rows)
```

Такие запросы полезны, например, для выявления маршрутов, которым не назначены автобусы:
```bash
postgres=# select *
from bus b
left join model_bus mb on b.id_model=mb.id
where mb.id is null;
 id |     route      | id_model | id | name
----+----------------+----------+----+------
  6 | Москва-Иваново |          |    |
  7 | Москва-Саратов |          |    |
  8 | Москва-Воронеж |          |    |
(3 rows)
```

Или, например, для выявления автобусов, которые без маршрутов:
```bash
postgres=# select *
from bus b
right join model_bus mb on b.id_model=mb.id
where b.id
    is null;
 id | route | id_model | id |  name
----+-------+----------+----+--------
    |       |          |  5 | НЕФАЗ
    |       |          |  6 | ЗиС
    |       |          |  4 | МАЗ
    |       |          |  7 | Икарус
(4 rows)
```

3. Кросс соединение двух таблиц:
```bash
postgres=# select *
from bus b
cross join model_bus mb;

 id |      route       | id_model | id |  name
----+------------------+----------+----+--------
  1 | Москва-Болшево   |        1 |  1 | ПАЗ
  1 | Москва-Болшево   |        1 |  2 | ЛИАЗ
  1 | Москва-Болшево   |        1 |  3 | MAN
  1 | Москва-Болшево   |        1 |  4 | МАЗ
  1 | Москва-Болшево   |        1 |  5 | НЕФАЗ
  1 | Москва-Болшево   |        1 |  6 | ЗиС
  1 | Москва-Болшево   |        1 |  7 | Икарус
  2 | Москва-Пушкино   |        1 |  1 | ПАЗ
  2 | Москва-Пушкино   |        1 |  2 | ЛИАЗ
  2 | Москва-Пушкино   |        1 |  3 | MAN
  2 | Москва-Пушкино   |        1 |  4 | МАЗ
  2 | Москва-Пушкино   |        1 |  5 | НЕФАЗ
  2 | Москва-Пушкино   |        1 |  6 | ЗиС
  2 | Москва-Пушкино   |        1 |  7 | Икарус
  3 | Москва-Ярославль |        2 |  1 | ПАЗ
  3 | Москва-Ярославль |        2 |  2 | ЛИАЗ
  3 | Москва-Ярославль |        2 |  3 | MAN
  3 | Москва-Ярославль |        2 |  4 | МАЗ
  3 | Москва-Ярославль |        2 |  5 | НЕФАЗ
  3 | Москва-Ярославль |        2 |  6 | ЗиС
  3 | Москва-Ярославль |        2 |  7 | Икарус
  4 | Москва-Кострома  |        2 |  1 | ПАЗ
  4 | Москва-Кострома  |        2 |  2 | ЛИАЗ
  4 | Москва-Кострома  |        2 |  3 | MAN
  4 | Москва-Кострома  |        2 |  4 | МАЗ
  4 | Москва-Кострома  |        2 |  5 | НЕФАЗ
  4 | Москва-Кострома  |        2 |  6 | ЗиС
  4 | Москва-Кострома  |        2 |  7 | Икарус
  5 | Москва-Волгорад  |        3 |  1 | ПАЗ
  5 | Москва-Волгорад  |        3 |  2 | ЛИАЗ
  5 | Москва-Волгорад  |        3 |  3 | MAN
  5 | Москва-Волгорад  |        3 |  4 | МАЗ
  5 | Москва-Волгорад  |        3 |  5 | НЕФАЗ
  5 | Москва-Волгорад  |        3 |  6 | ЗиС
  5 | Москва-Волгорад  |        3 |  7 | Икарус
  6 | Москва-Иваново   |          |  1 | ПАЗ
  6 | Москва-Иваново   |          |  2 | ЛИАЗ
  6 | Москва-Иваново   |          |  3 | MAN
  6 | Москва-Иваново   |          |  4 | МАЗ
  6 | Москва-Иваново   |          |  5 | НЕФАЗ
  6 | Москва-Иваново   |          |  6 | ЗиС
  6 | Москва-Иваново   |          |  7 | Икарус
  7 | Москва-Саратов   |          |  1 | ПАЗ
  7 | Москва-Саратов   |          |  2 | ЛИАЗ
  7 | Москва-Саратов   |          |  3 | MAN
  7 | Москва-Саратов   |          |  4 | МАЗ
  7 | Москва-Саратов   |          |  5 | НЕФАЗ
  7 | Москва-Саратов   |          |  6 | ЗиС
  7 | Москва-Саратов   |          |  7 | Икарус
  8 | Москва-Воронеж   |          |  1 | ПАЗ
  8 | Москва-Воронеж   |          |  2 | ЛИАЗ
  8 | Москва-Воронеж   |          |  3 | MAN
  8 | Москва-Воронеж   |          |  4 | МАЗ
  8 | Москва-Воронеж   |          |  5 | НЕФАЗ
  8 | Москва-Воронеж   |          |  6 | ЗиС
  8 | Москва-Воронеж   |          |  7 | Икарус
(56 rows)
```

4. Полное соединение двух таблиц:
```bash
postgres=# select *
from bus b
full join model_bus mb on b.id_model=mb.id;
 id |      route       | id_model | id |  name
----+------------------+----------+----+--------
  1 | Москва-Болшево   |        1 |  1 | ПАЗ
  2 | Москва-Пушкино   |        1 |  1 | ПАЗ
  3 | Москва-Ярославль |        2 |  2 | ЛИАЗ
  4 | Москва-Кострома  |        2 |  2 | ЛИАЗ
  5 | Москва-Волгорад  |        3 |  3 | MAN
  6 | Москва-Иваново   |          |    |
  7 | Москва-Саратов   |          |    |
  8 | Москва-Воронеж   |          |    |
    |                  |          |  5 | НЕФАЗ
    |                  |          |  6 | ЗиС
    |                  |          |  4 | МАЗ
    |                  |          |  7 | Икарус
(12 rows)

postgres=# select *
from bus b
full join model_bus mb on b.id_model=mb.id
where b.id is null or mb.id is null;
 id |     route      | id_model | id |  name
----+----------------+----------+----+--------
  6 | Москва-Иваново |          |    |
  7 | Москва-Саратов |          |    |
  8 | Москва-Воронеж |          |    |
    |                |          |  5 | НЕФАЗ
    |                |          |  6 | ЗиС
    |                |          |  4 | МАЗ
    |                |          |  7 | Икарус
(7 rows)
```

5. Для более-менее осмысленного запроса, в котором будем использовать разные типы соединений, создадим третью таблицу - связка маршрутов и дней недели - 
своего рода расписание:
```bash
postgres=# create table schedule (id_bus int, day int);
CREATE TABLE
postgres=# insert into schedule values (1,1),(1,5),(2,2),(3,5),(4,6),(4,0),(5,0);
INSERT 0 7
```

Теперь выберем все маршруты, которые идут из Москвы:
```bash
postgres=# select b.route, (select case
when sched.day=1 then 'ПН'
when sched.day=2 then 'ВТ'
when sched.day=3 then 'СР'
when sched.day=4 then 'ЧТ'
when sched.day=5 then 'ПТ'
when sched.day=6 then 'СБ'
when sched.day=0 then 'ВС'
END) as day_name, mb.name
from bus b
join schedule sched
    on b.id=sched.id_bus
left join model_bus mb on b.id_model=mb.id
where b.route like 'Москва%';
      route       | day_name | name
------------------+----------+------
 Москва-Болшево   | ПН       | ПАЗ
 Москва-Болшево   | ПТ       | ПАЗ
 Москва-Пушкино   | ВТ       | ПАЗ
 Москва-Ярославль | ПТ       | ЛИАЗ
 Москва-Кострома  | СБ       | ЛИАЗ
 Москва-Кострома  | ВС       | ЛИАЗ
 Москва-Волгорад  | ВС       | MAN
(7 rows)
```
Таким образом, мы узнали, по каким дням и на каких моделях транспорта выполняются рейсы из Москвы.

Теперь выберем все маршруты, которые идут в Кострому:
```bash
postgres=# select b.route, (select case
when sched.day=1 then 'ПН'
when sched.day=2 then 'ВТ'
when sched.day=3 then 'СР'
when sched.day=4 then 'ЧТ'
when sched.day=5 then 'ПТ'
when sched.day=6 then 'СБ'
when sched.day=0 then 'ВС'
END) as day_name, mb.name
from bus b
join schedule sched
    on b.id=sched.id_bus
left join model_bus mb on b.id_model=mb.id
where b.route like '%Кострома';
      route      | day_name | name
-----------------+----------+------
 Москва-Кострома | СБ       | ЛИАЗ
 Москва-Кострома | ВС       | ЛИАЗ
(2 rows)
```

6. Выполнен в процессе выполнения задания.
7. Структуры таблиц:
```bash
postgres=# \d bus;
                             Table "public.bus"
  Column  |  Type   | Collation | Nullable |             Default
----------+---------+-----------+----------+---------------------------------
 id       | integer |           | not null | nextval('bus_id_seq'::regclass)
 route    | text    |           |          |
 id_model | integer |           |          |

postgres=# \d model_bus;
                            Table "public.model_bus"
 Column |  Type   | Collation | Nullable |                Default
--------+---------+-----------+----------+---------------------------------------
 id     | integer |           | not null | nextval('model_bus_id_seq'::regclass)
 name   | text    |           |          |

postgres=# \d schedule;
              Table "public.schedule"
 Column |  Type   | Collation | Nullable | Default
--------+---------+-----------+----------+---------
 id_bus | integer |           |          |
 day    | integer |           |          |
```
