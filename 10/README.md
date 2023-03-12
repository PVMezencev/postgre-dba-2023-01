## Блокировки.

1. Для того, чтоб информация о транзакциях попадала в журнал логов, нужно включить *log_lock_waits* и установить 
в *deadlock_timeout* таймаут в мс.
    - Подключимся под суперпользователем, проверим текущие настройки:
    ```bash
    devops0@otus-pg:~$ sudo -u postgres 
    ```
    - Создадим отдельную БД locks:
    ```bash
    postgres=# create database locks;
    postgres=# \c locks;
    ```
    - Проверим текущие настройки:
    ```bash
    locks=# SHOW deadlock_timeout;
    deadlock_timeout
    ------------------
    1s
    (1 row)
    
    locks=# SHOW log_lock_waits;
    log_lock_waits
    ----------------
    off
    (1 row)
    ```
    - Установим нужные нам значения:
    ```bash
    locks=# ALTER SYSTEM SET log_lock_waits = on;
    locks=# ALTER SYSTEM SET deadlock_timeout = 200;
    locks=# SELECT pg_reload_conf(); -- Попросим процессы сервере перечитать конфигурационные файлы.
    
    ```
    - Проверим текущие настройки:
    ```bash
    locks=# SHOW log_lock_waits;
    log_lock_waits
    ----------------
    on
    (1 row)
    
    locks=# SHOW deadlock_timeout;
    deadlock_timeout
    ------------------
    200ms
    (1 row)

    ```
    - Создадим таблицу с тестовыми данными:
    ```bash
   locks=# CREATE TABLE accounts(acc_no integer PRIMARY KEY, amount numeric); INSERT INTO accounts VALUES (1,1000.00), (2,2000.00), (3,3000.00);
   CREATE TABLE
   INSERT 0 3
    ```
    - Далее я создал 3 параллельных сеанса, используя утилиту screen, для тех, что работают в psql сессии назвал по 
   номерам процессов, которые были получены при подключении к postgresql, этот номер получил вызовом функции:
    ```bash
    locks=# SELECT pg_backend_pid();    
    ```
    - Сеанс 1 - начинаем транзакцию, запускаем команду обновления данных в одной строке:
    ```bash
    # PID 52286
    locks=# BEGIN;
    BEGIN
    locks=*# UPDATE accounts SET amount = amount + 100 WHERE acc_no = 1;
    UPDATE 1
    locks=*# <-- транзакция не завершена.
    ```
    - Сеанс 2 - начинаем транзакцию, запускаем команду обновления данных в той же самой строке:
    ```bash
    # PID 52290
    locks=# BEGIN;
    BEGIN
    locks=*# UPDATE accounts SET amount = amount + 100 WHERE acc_no = 1;
    <-- повисаем в блокировке...
    ```
    - В это время в журнале логов (в третьей сессии):
    ```bash
   devops0@otus-pg:~$ sudo tail -f /var/log/postgresql/postgresql-14-main.log
   2023-03-12 20:15:41.440 +05 [52290] postgres@locks LOG:  process 52290 still waiting for ShareLock on transaction 747 after 200.160 ms
    # процесс 52290 ожидает завершение блокировки транзакции 747 более 200.160 мс.
   2023-03-12 20:15:41.440 +05 [52290] postgres@locks DETAIL:  Process holding the lock: 52286. Wait queue: 52290.
    # Процесс 52286 удерживает блокировку, которую ждем 52290.
   2023-03-12 20:15:41.440 +05 [52290] postgres@locks CONTEXT:  while updating tuple (0,12) in relation "accounts"
    # Все это происходит в контексте обновления строки в таблице accounts.
   2023-03-12 20:15:41.440 +05 [52290] postgres@locks STATEMENT:  UPDATE accounts SET amount = amount + 100 WHERE acc_no = 1;
    # Запрос.
    
    ```
    - Сеанс 1 - зафиксируем изменения транзакции:
    ```bash
   # PID 52286
   locks=*# COMMIT;
   COMMIT
    ```
    - Сеанс 2 - блокировка снимается, можем зафиксировать изменения тоже:
    ```bash
   # PID 52290
   UPDATE 1 <-- обновление прошло.
   locks=*# COMMIT;
   COMMIT
    ```
    - Тем временем получаем новую порцию информации в лог:
    ```bash
   2023-03-12 20:18:26.114 +05 [52290] postgres@locks LOG:  process 52290 acquired ShareLock on transaction 747 after 164874.101 ms
    # Процесс 52290 получил блокировку ShareLock, при которой может завершить свою задачу (спустя 164874.101 мс).
   2023-03-12 20:18:26.114 +05 [52290] postgres@locks CONTEXT:  while updating tuple (0,12) in relation "accounts"
   2023-03-12 20:18:26.114 +05 [52290] postgres@locks STATEMENT:  UPDATE accounts SET amount = amount + 100 WHERE acc_no = 1;
    ```
3. Обновление одной и той же строки тремя командами UPDATE в разных сеансах.
   - Заголовок:
    ```bash
    
    ```