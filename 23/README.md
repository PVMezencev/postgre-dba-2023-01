## Триггеры, поддержка заполнения витрин.

1. Используя скрипт из задания, создадим необходимые таблицы с данными:
```sql
-- товары:
DROP TABLE IF EXISTS goods CASCADE;
CREATE TABLE goods
(
    goods_id   integer PRIMARY KEY,
    good_name  varchar(63)    NOT NULL,
    good_price numeric(12, 2) NOT NULL CHECK (good_price > 0.0)
);


INSERT INTO goods (goods_id, good_name, good_price)
VALUES (1, 'Спички хозайственные', .50),
       (2, 'Автомобиль Ferrari FXX K', 185000000.01);

-- Продажи
DROP TABLE IF EXISTS sales CASCADE;
CREATE TABLE sales
(
    sales_id   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    good_id    integer REFERENCES goods (goods_id),
    sales_time timestamp with time zone DEFAULT now(),
    sales_qty  integer CHECK (sales_qty > 0)
);

INSERT INTO sales (good_id, sales_qty)
VALUES (1, 10),
       (1, 1),
       (1, 120),
       (2, 1);

-- с увеличением объёма данных отчет стал создаваться медленно
-- Принято решение денормализовать БД, создать таблицу
DROP TABLE IF EXISTS good_sum_mart CASCADE;
CREATE TABLE good_sum_mart
(
    good_name varchar(63)    NOT NULL,
    sum_sale  numeric(16, 2) NOT NULL
);

```

2. Заполним данные таблицы `good_sum_mart`, используя запрос для отчёта:
```sql
INSERT INTO good_sum_mart
SELECT G.good_name, sum(G.good_price * S.sales_qty)
FROM goods G
         INNER JOIN sales S ON S.good_id = G.goods_id
GROUP BY G.good_name;
```

3. Для проверки выполним запрос отчета и запрос из таблицы:
```bash
postgres=# SELECT * FROM good_sum_mart;
        good_name         |   sum_sale
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Спички хозайственные     |        65.50
(2 rows)

postgres=# SELECT G.good_name, sum(G.good_price * S.sales_qty)
FROM goods G
         INNER JOIN sales S ON S.good_id = G.goods_id
GROUP BY G.good_name;
        good_name         |     sum
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Спички хозайственные     |        65.50
(2 rows)
```

4. Создадим функцию для триггера по новой продаже. Функция должна увеличивать сумму продаж по товару, если запись с таким товаром уже есть, либо создавать новую запись
с именем товара и суммой продажи:
```sql
DROP FUNCTION IF EXISTS new_sale CASCADE;
CREATE OR REPLACE FUNCTION new_sale()
    RETURNS trigger
AS
$N_SALE$
BEGIN
    IF EXISTS (
        SELECT GSM.good_name
        FROM good_sum_mart GSM
            INNER JOIN goods G
            ON NEW.good_id = G.goods_id
        WHERE GSM.good_name = G.good_name
        )
    THEN
        UPDATE good_sum_mart GSM
        SET sum_sale = sum_sale + (G.good_price * NEW.sales_qty)
        FROM sales S
          INNER JOIN goods G ON G.goods_id = NEW.good_id
        WHERE GSM.good_name = G.good_name;
    ELSE
        INSERT INTO good_sum_mart
        SELECT G.good_name, (G.good_price * NEW.sales_qty) sum_sale
        FROM goods G
        WHERE G.goods_id = NEW.good_id;
    END IF;
    RETURN NEW;
END;
$N_SALE$
    LANGUAGE plpgsql;
```
5. Создаем триггер, который будет запускать функцию `new_sale` после события вставки в таблицу `sales`:
```sql
CREATE TRIGGER tr_new_sale
    AFTER INSERT
    ON sales
FOR EACH ROW
EXECUTE PROCEDURE new_sale();
```

6. Проведем продажу 5 коробков спичек:
```sql
INSERT INTO sales (good_id, sales_qty)
VALUES (1, 5);
```

7. Выполним запросы отчета и таблицы витрины, для проверки:
```bash
postgres=# SELECT G.good_name, sum(G.good_price * S.sales_qty)
FROM goods G
         INNER JOIN sales S ON S.good_id = G.goods_id
GROUP BY G.good_name;
        good_name         |     sum
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Спички хозайственные     |        68.00
(2 rows)

postgres=# SELECT * FROM good_sum_mart;
        good_name         |   sum_sale
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Спички хозайственные     |        68.00
(2 rows)
```
8. Создадим новый товар, и продадим его для проверки добавления записи о новом товаре в таблицу витрины. Для дополнительной проверки продадим одновременно еще спички,
таким образом тестируется обработка триггером вставки нескольких строк (FOR EACH ROW):
```sql
INSERT INTO goods (goods_id, good_name, good_price)
VALUES (3, 'Молоко', 12.50);

INSERT INTO sales (good_id, sales_qty)
VALUES
    (1, 1), (3, 1), (3, 2);
```
Продано 3 молока по цене 12.50 на сумму 37.50, 1 коробок спичек по цене 0.5.

9. Повторяем проверочные выборки отчета и витрины:
```bash
postgres=# SELECT * FROM good_sum_mart;
        good_name         |   sum_sale
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Спички хозайственные     |        68.50
 Молоко                   |        37.50
(3 rows)

postgres=# SELECT G.good_name, sum(G.good_price * S.sales_qty)
FROM goods G
         INNER JOIN sales S ON S.good_id = G.goods_id
GROUP BY G.good_name;
        good_name         |     sum
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Спички хозайственные     |        68.50
 Молоко                   |        37.50
(3 rows) 
```

10. Создадим функцию для триггера по возврату. Функция должна уменьшать сумму продаж по возвращаемому товару в таблице витрины:
```sql
DROP FUNCTION IF EXISTS refund_sale CASCADE;
CREATE OR REPLACE FUNCTION refund_sale()
    RETURNS trigger
AS
$R_SALE$
BEGIN
    UPDATE good_sum_mart GSM
    SET sum_sale = sum_sale - (G.good_price * OLD.sales_qty)
    FROM sales S
             INNER JOIN goods G ON G.goods_id = OLD.good_id
    WHERE GSM.good_name = G.good_name;
    RETURN OLD;
END;
$R_SALE$
    LANGUAGE plpgsql;
```

11. Создаем триггер, который будет запускать функцию `refund_sale` перед событием удаления из таблицы `sales`:
```sql
CREATE TRIGGER refund_sale
    BEFORE DELETE
    ON sales
    FOR EACH ROW
EXECUTE PROCEDURE refund_sale();
```

12. Выполним запрос списка продаж:
```bash
postgres=# SELECT * FROM sales;
 sales_id | good_id |          sales_time           | sales_qty
----------+---------+-------------------------------+-----------
        1 |       1 | 2023-05-06 13:35:44.291206+05 |        10
        2 |       1 | 2023-05-06 13:35:44.291206+05 |         1
        3 |       1 | 2023-05-06 13:35:44.291206+05 |       120
        4 |       2 | 2023-05-06 13:35:44.291206+05 |         1
        5 |       1 | 2023-05-06 13:37:11.981355+05 |         5
        6 |       1 | 2023-05-06 13:39:27.578829+05 |         1
        7 |       3 | 2023-05-06 13:39:27.578829+05 |         1
        8 |       3 | 2023-05-06 13:39:27.578829+05 |         2
(8 rows)
```

13. Выполним запрос удаления 3-х последних продаж:
```sql
DELETE FROM sales WHERE sales_id IN (6,7,8);
```

14. Выполним запрос списка продаж:
```bash
postgres=# SELECT * FROM sales;
 sales_id | good_id |          sales_time           | sales_qty
----------+---------+-------------------------------+-----------
        1 |       1 | 2023-05-06 13:35:44.291206+05 |        10
        2 |       1 | 2023-05-06 13:35:44.291206+05 |         1
        3 |       1 | 2023-05-06 13:35:44.291206+05 |       120
        4 |       2 | 2023-05-06 13:35:44.291206+05 |         1
        5 |       1 | 2023-05-06 13:37:11.981355+05 |         5
(5 rows)
```

15. Повторяем проверочные выборки отчета и витрины:
```bash
postgres=# SELECT G.good_name, sum(G.good_price * S.sales_qty)
FROM goods G
         INNER JOIN sales S ON S.good_id = G.goods_id
GROUP BY G.good_name;
        good_name         |     sum
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Спички хозайственные     |        68.00
(2 rows)

postgres=# SELECT * FROM good_sum_mart;
        good_name         |   sum_sale
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Спички хозайственные     |        68.00
 Молоко                   |         0.00
(3 rows)
```

16. Создадим функцию для триггера по изменению продажи (добавление товара или частичный возврат). Если происходит добавление товара, функция должна увеличивать
сумму в таблице витрины на сумму разницы, и наоборот, если происходит частичный возврат, то функция должна уменьшать сумму на сумму разницы:
```sql
DROP FUNCTION IF EXISTS change_sale CASCADE;
CREATE OR REPLACE FUNCTION change_sale()
    RETURNS trigger
AS
$CH_SALE$
BEGIN
    IF (NEW.sales_qty > OLD.sales_qty)
    THEN
        UPDATE good_sum_mart GSM
        SET sum_sale = sum_sale + (G.good_price * (NEW.sales_qty - OLD.sales_qty))
        FROM sales S
                 INNER JOIN goods G ON G.goods_id = OLD.good_id
        WHERE GSM.good_name = G.good_name;
    ELSE
        UPDATE good_sum_mart GSM
        SET sum_sale = sum_sale - (G.good_price * (OLD.sales_qty - NEW.sales_qty))
        FROM sales S
                 INNER JOIN goods G ON G.goods_id = OLD.good_id
        WHERE GSM.good_name = G.good_name;
    END IF;
    RETURN NEW;
END;
$CH_SALE$
    LANGUAGE plpgsql;
```

17. Создаем триггер, который будет запускать функцию `change_sale` после события изменения записей в таблице `sales`:
```sql
CREATE TRIGGER change_sale
    AFTER UPDATE
    ON sales
    FOR EACH ROW
EXECUTE PROCEDURE change_sale();
```

18. Выполним продажу нескольких товаров:
```sql
INSERT INTO sales (good_id, sales_qty)
VALUES
    (1, 1), (3, 1), (3, 2);
```

19. Выполним запрос списка продаж:
```bash
postgres=# SELECT * FROM sales;
 sales_id | good_id |          sales_time           | sales_qty
----------+---------+-------------------------------+-----------
        1 |       1 | 2023-05-06 13:35:44.291206+05 |        10
        2 |       1 | 2023-05-06 13:35:44.291206+05 |         1
        3 |       1 | 2023-05-06 13:35:44.291206+05 |       120
        4 |       2 | 2023-05-06 13:35:44.291206+05 |         1
        5 |       1 | 2023-05-06 13:37:11.981355+05 |         5 <-- отсюда уберём 3 коробка спичек
        9 |       1 | 2023-05-06 13:56:46.538929+05 |         1
       10 |       3 | 2023-05-06 13:56:46.538929+05 |         1
       11 |       3 | 2023-05-06 13:56:46.538929+05 |         2 <-- сюда добавим 3 пакета молока
(8 rows)
```

20. Повторяем проверочные выборки отчета и витрины перед добавлением молока:
```bash
postgres=# SELECT * FROM good_sum_mart;
        good_name         |   sum_sale
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Спички хозайственные     |        68.50
 Молоко                   |        37.50
(3 rows)

postgres=# SELECT G.good_name, sum(G.good_price * S.sales_qty)
FROM goods G
         INNER JOIN sales S ON S.good_id = G.goods_id
GROUP BY G.good_name;
        good_name         |     sum
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Спички хозайственные     |        68.50
 Молоко                   |        37.50
(3 rows) 
```

21. Добавим 3 пакета молока в последнюю продажу:
```sql
UPDATE sales
SET sales_qty = 5
WHERE sales_id = 11;
```

22. Выполним запрос списка продаж:
```bash
postgres=# SELECT * FROM sales;
 sales_id | good_id |          sales_time           | sales_qty
----------+---------+-------------------------------+-----------
        1 |       1 | 2023-05-06 13:35:44.291206+05 |        10
        2 |       1 | 2023-05-06 13:35:44.291206+05 |         1
        3 |       1 | 2023-05-06 13:35:44.291206+05 |       120
        4 |       2 | 2023-05-06 13:35:44.291206+05 |         1
        5 |       1 | 2023-05-06 13:37:11.981355+05 |         5
        9 |       1 | 2023-05-06 13:56:46.538929+05 |         1
       10 |       3 | 2023-05-06 13:56:46.538929+05 |         1
       11 |       3 | 2023-05-06 13:56:46.538929+05 |         5 <-- увеличилось на 3
(8 rows)
```

23. Повторяем проверочные выборки отчета и витрины:
```bash
postgres=# SELECT G.good_name, sum(G.good_price * S.sales_qty)
FROM goods G
         INNER JOIN sales S ON S.good_id = G.goods_id
GROUP BY G.good_name;
        good_name         |     sum
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Спички хозайственные     |        68.50
 Молоко                   |        75.00
(2 rows)

postgres=# SELECT * FROM good_sum_mart;
        good_name         |   sum_sale
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Спички хозайственные     |        68.50
 Молоко                   |        75.00
(3 rows)
```

24. Уберём 3 коробка спичек из продажи, которая была ранее:
```sql
UPDATE sales
SET sales_qty = 2
WHERE sales_id = 5;
```

25. Выполним запрос списка продаж:
```bash
postgres=# SELECT * FROM sales;
 sales_id | good_id |          sales_time           | sales_qty
----------+---------+-------------------------------+-----------
        1 |       1 | 2023-05-06 13:35:44.291206+05 |        10
        2 |       1 | 2023-05-06 13:35:44.291206+05 |         1
        3 |       1 | 2023-05-06 13:35:44.291206+05 |       120
        4 |       2 | 2023-05-06 13:35:44.291206+05 |         1
        9 |       1 | 2023-05-06 13:56:46.538929+05 |         1
       10 |       3 | 2023-05-06 13:56:46.538929+05 |         1
       11 |       3 | 2023-05-06 13:56:46.538929+05 |         5
        5 |       1 | 2023-05-06 13:37:11.981355+05 |         2 <-- уменьшилось на 3
(8 rows)
```

26. Повторяем проверочные выборки отчета и витрины:
```bash
postgres=# SELECT G.good_name, sum(G.good_price * S.sales_qty)
FROM goods G
         INNER JOIN sales S ON S.good_id = G.goods_id
GROUP BY G.good_name;
        good_name         |   sum_sale
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Молоко                   |        75.00
 Спички хозайственные     |        67.00
(2 rows)

postgres=# SELECT * FROM good_sum_mart;
        good_name         |   sum_sale
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Молоко                   |        75.00
 Спички хозайственные     |        67.00
(3 rows)
```

(*) Cхема (витрина+триггер) предпочтительнее отчета, создаваемого "по требованию" тем, что в отчёт берется цена товара из таблицы-справочника товара, актуальная на момент запроса, а сумма
продаж всего высчитывается на лету. Если изменить цену, то сумма будет рассчитываться по новым ценам. В случае с витриной, сумма продаж сохраняется в момент продажи с ценой на момент продажи
Прошлые продажи не будут зависеть от изменения цены в будущем.

Для примера изменим цену на спички - увеличим в 7 раз (0.5 * 7 = 3.5):
```sql
UPDATE goods
SET good_price = 3.5
WHERE goods_id = 1;
```

Продаж не было, мы просто изменили цену. Повторяем проверочные выборки отчета и витрины:
```bash
postgres=# SELECT G.good_name, sum(G.good_price * S.sales_qty)
FROM goods G
         INNER JOIN sales S ON S.good_id = G.goods_id
GROUP BY G.good_name;
        good_name         |     sum
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Спички хозайственные     |       469.00 <-- неверная сумма
 Молоко                   |        75.00
(3 rows)

postgres=# SELECT * FROM good_sum_mart;
        good_name         |   sum_sale
--------------------------+--------------
 Автомобиль Ferrari FXX K | 185000000.01
 Молоко                   |        75.00 
 Спички хозайственные     |        67.00 <-- верная сумма
(3 rows)
```

Видим, что сумма продаж в отчете пересчиталась по новой цене, а сумма в витрине осталась прежней.