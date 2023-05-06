-- ДЗ тема: триггеры, поддержка заполнения витрин

DROP SCHEMA IF EXISTS pract_functions CASCADE;
CREATE SCHEMA pract_functions;

SET search_path = pract_functions, publ;

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

-- отчет:
SELECT G.good_name, sum(G.good_price * S.sales_qty)
FROM goods G
         INNER JOIN sales S ON S.good_id = G.goods_id
GROUP BY G.good_name;

-- с увеличением объёма данных отчет стал создаваться медленно
-- Принято решение денормализовать БД, создать таблицу
DROP TABLE IF EXISTS good_sum_mart CASCADE;
CREATE TABLE good_sum_mart
(
    good_name varchar(63)    NOT NULL,
    sum_sale  numeric(16, 2) NOT NULL
);

INSERT INTO good_sum_mart
SELECT G.good_name, sum(G.good_price * S.sales_qty)
FROM goods G
         INNER JOIN sales S ON S.good_id = G.goods_id
GROUP BY G.good_name;

-- Создать триггер (на таблице sales) для поддержки.
-- Подсказка: не забыть, что кроме INSERT есть еще UPDATE и DELETE

-- Триггерная функция для новой продажи.
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

-- Создать триггер на новую продажу.
DROP TRIGGER IF EXISTS tr_new_sale ON sales;

CREATE TRIGGER tr_new_sale
    AFTER INSERT
    ON sales
FOR EACH ROW
EXECUTE PROCEDURE new_sale();


SELECT * FROM good_sum_mart;

INSERT INTO sales (good_id, sales_qty)
VALUES (1, 5);

INSERT INTO goods (goods_id, good_name, good_price)
VALUES (3, 'Молоко', 12.50);

INSERT INTO sales (good_id, sales_qty)
VALUES
    (1, 1), (3, 1), (3, 2);


-- Триггерная функция для удаления продажи (возврат).
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

-- Создать триггер для удаления продажи.
DROP TRIGGER IF EXISTS tr_refund_sale ON sales;

CREATE TRIGGER refund_sale
    BEFORE DELETE
    ON sales
    FOR EACH ROW
EXECUTE PROCEDURE refund_sale();

DELETE FROM sales WHERE sales_id IN (6,7,8);


-- Триггерная функция для изменения продажи (добавление товара или частичный возврат).
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

-- Создать триггер для изменения продажи.
DROP TRIGGER IF EXISTS change_sale ON sales;

CREATE TRIGGER change_sale
    AFTER UPDATE
    ON sales
    FOR EACH ROW
EXECUTE PROCEDURE change_sale();


INSERT INTO sales (good_id, sales_qty)
VALUES
    (1, 1), (3, 1), (3, 2);

UPDATE sales
SET sales_qty = 5
WHERE sales_id = 11;

UPDATE sales
SET sales_qty = 2
WHERE sales_id = 5;

-- Чем такая схема (витрина+триггер) предпочтительнее отчета, создаваемого "по требованию" (кроме производительности)?
-- Подсказка: В реальной жизни возможны изменения цен.

UPDATE goods
SET good_price = 3.5
WHERE goods_id = 1;
