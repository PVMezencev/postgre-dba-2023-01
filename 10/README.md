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
2. Обновление одной и той же строки тремя командами UPDATE в разных сеансах.
   - Создаем представление для удобного отслеживания типов блокировок:
    ```sql
   CREATE VIEW locks_v AS
   SELECT pid,
          locktype,
          CASE locktype
            WHEN 'relation' THEN relation::regclass::text
            WHEN 'transactionid' THEN transactionid::text
            WHEN 'tuple' THEN relation::regclass::text||':'||tuple::text
          END AS lockid,
          mode,
          granted
   FROM pg_locks
   WHERE locktype in ('relation','transactionid','tuple')
   AND (locktype != 'relation' OR relation = 'accounts'::regclass);
    ```
   - Будем работать в 4-х сеансах: 3 будут делать обновления, 4-ый для запросов отслеживания блокировок. 
   - Запустим все сеансы, в контрольном сеансе выполним запросы перед началом:
    ```bash
   locks=# SELECT * FROM locks_v;
   pid | locktype | lockid | mode | granted
   -----+----------+--------+------+---------
   (0 rows)
   
   # Блокировок нет
   
   locks=# SELECT pid, wait_event_type, wait_event, pg_blocking_pids(pid)
   FROM pg_stat_activity
   WHERE backend_type = 'client backend' ORDER BY pid;
   pid  | wait_event_type | wait_event | pg_blocking_pids
   -------+-----------------+------------+------------------
   53413 | Client          | ClientRead | {}
   53422 | Client          | ClientRead | {}
   53434 | Client          | ClientRead | {}
   53445 |                 |            | {}
   (4 rows)
   # Есть 4 сеанса
    
    ```
   - 1 сеанс - начинаем транзакцию, получаем её идентификатор и идентификатор сеанса, выполняем обновление 1-ой строки:
    ```bash
   locks=# BEGIN;
   BEGIN
   locks=*# SELECT txid_current(), pg_backend_pid();
   txid_current | pg_backend_pid
   --------------+----------------
   758 |          53413
   (1 row)
   
   
   locks=*# UPDATE accounts SET amount = amount + 100.00 WHERE acc_no  = 1;
   UPDATE 1
   locks=*# <-- транзакция не завершена
    ```
   - Контрольный сеанс:
    ```bash
   locks=# SELECT * FROM locks_v;
   pid  |   locktype    |  lockid  |       mode       | granted
   -------+---------------+----------+------------------+---------
   53413 | relation      | accounts | RowExclusiveLock | t # Блокировка таблицы обновляемой строки транзакцией первого сеанса
   53413 | transactionid | 758      | ExclusiveLock    | t # Блокировка номера транзакции в режиме исключительной блокировки транзакцией первого сеанса
   (2 rows)
   
      locks=# SELECT pid, wait_event_type, wait_event, pg_blocking_pids(pid)
   FROM pg_stat_activity
   WHERE backend_type = 'client backend' ORDER BY pid;
   pid  | wait_event_type | wait_event | pg_blocking_pids
   -------+-----------------+------------+------------------
   53413 | Client          | ClientRead | {}
   53422 | Client          | ClientRead | {}
   53434 | Client          | ClientRead | {}
   53445 |                 |            | {}
   (4 rows)
   # Процессы пока не блокируются
    ```
   - 2 сеанс - аналогично первому начинаем транзакцию, получаем идентификаторы, запускаем обновление строки:
    ```bash
   locks=# BEGIN;
   BEGIN
   locks=*# SELECT txid_current(), pg_backend_pid();
   txid_current | pg_backend_pid
   --------------+----------------
   760 |          53422
   (1 row)
   locks=*# UPDATE accounts SET amount = amount + 100.00 WHERE acc_no  = 1;
   < -- обновление заблокировано
    ```
   - Контрольный сеанс:
    ```bash
   locks=# SELECT * FROM locks_v;
   pid  |   locktype    |   lockid   |       mode       | granted
   -------+---------------+------------+------------------+---------
   53413 | relation      | accounts   | RowExclusiveLock | t # Блокировка таблицы обновляемой строки транзакцией первого сеанса
   53422 | relation      | accounts   | RowExclusiveLock | t # Блокировка таблицы обновляемой строки транзакцией второго сеанса
   53422 | transactionid | 760        | ExclusiveLock    | t # Блокировка номера транзакции в режиме исключительной блокировки транзакцией второго сеанса
   53413 | transactionid | 758        | ExclusiveLock    | t # Блокировка номера транзакции в режиме исключительной блокировки транзакцией первого сеанса
   53422 | tuple         | accounts:1 | ExclusiveLock    | t # Транзакцией второго сеанса наложена блокировка на версию обновляемой строки.
   53422 | transactionid | 758        | ShareLock        | f # Транзакция второго сеанса получила блокировку номера транзакции первого сеанса, доступ запрещён, ожидается завершение 758 тр-и. 
   (6 rows)
   
   
   locks=# SELECT pid, wait_event_type, wait_event, pg_blocking_pids(pid)
   FROM pg_stat_activity
   WHERE backend_type = 'client backend' ORDER BY pid;
   pid  | wait_event_type |  wait_event   | pg_blocking_pids
   -------+-----------------+---------------+------------------
   53413 | Client          | ClientRead    | {}
   53422 | Lock            | transactionid | {53413} # Обновление второго сеанса заблокировано транзакцией из первого сеанса
   53434 | Client          | ClientRead    | {}
   53445 |                 |               | {}
   (4 rows)
    ```
   - 3 сеанс - запускаем трназакцию, получаем идентификаторы, начинаем обновление:
    ```bash
   locks=# BEGIN;
   BEGIN
   locks=*# SELECT txid_current(), pg_backend_pid();
   txid_current | pg_backend_pid
   --------------+----------------
   761 |          53434
   (1 row)
   locks=*# UPDATE accounts SET amount = amount + 100.00 WHERE acc_no  = 1;
   < -- обновление заблокировано
    ```
   - Контрольный сеанс:
    ```bash
   locks=# SELECT * FROM locks_v;
   pid  |   locktype    |   lockid   |       mode       | granted
   -------+---------------+------------+------------------+---------
   53434 | relation      | accounts   | RowExclusiveLock | t # Блокировка таблицы обновляемой строки транзакцией третьего сеанса
   53413 | relation      | accounts   | RowExclusiveLock | t # Блокировка таблицы обновляемой строки транзакцией первого сеанса
   53422 | relation      | accounts   | RowExclusiveLock | t # Блокировка таблицы обновляемой строки транзакцией второго сеанса
   53422 | transactionid | 760        | ExclusiveLock    | t # Блокировка номера транзакции в режиме исключительной блокировки транзакцией второго сеанса
   53413 | transactionid | 758        | ExclusiveLock    | t # Блокировка номера транзакции в режиме исключительной блокировки транзакцией первого сеанса
   53434 | tuple         | accounts:1 | ExclusiveLock    | f # Транзакцией третьего сеанса попыталась заблокировать версию обновляемой строки, но версия удерживается транзакцией 760.
   53422 | tuple         | accounts:1 | ExclusiveLock    | t # Транзакцией второго сеанса наложена блокировка на версию обновляемой строки.
   53434 | transactionid | 761        | ExclusiveLock    | t # Блокировка номера транзакции в режиме исключительной блокировки транзакцией третьего сеанса
   53422 | transactionid | 758        | ShareLock        | f # Транзакция второго сеанса получила блокировку номера транзакции первого сеанса, доступ запрещён, ожидается завершение 758 тр-и.
   (9 rows)
   
   locks=# SELECT pid, wait_event_type, wait_event, pg_blocking_pids(pid)
   FROM pg_stat_activity
   WHERE backend_type = 'client backend' ORDER BY pid;
   pid  | wait_event_type |  wait_event   | pg_blocking_pids
   -------+-----------------+---------------+------------------
   53413 | Client          | ClientRead    | {}
   53422 | Lock            | transactionid | {53413} # Обновление второго сеанса заблокировано транзакцией из первого сеанса
   53434 | Lock            | tuple         | {53422} # Обновление третьего сеанса заблокировано транзакцией из второго сеанса
   53530 |                 |               | {}
   (4 rows)
    ```
   - 1 сеанс - применяем изменения:
    ```bash
   locks=*# COMMIT;
   COMMIT
   locks=# < -- транзакция завершилась.
    ```
   - Контрольный сеанс:
    ```bash
   locks=# SELECT * FROM locks_v;
   pid  |   locktype    |  lockid  |       mode       | granted
   -------+---------------+----------+------------------+---------
   53434 | relation      | accounts | RowExclusiveLock | t # Блокировка таблицы обновляемой строки транзакцией третьего сеанса
   53422 | relation      | accounts | RowExclusiveLock | t # Блокировка таблицы обновляемой строки транзакцией второго сеанса
   53422 | transactionid | 760      | ExclusiveLock    | t # Блокировка номера транзакции в режиме исключительной блокировки транзакцией второго сеанса
   53434 | transactionid | 760      | ShareLock        | f # Теперь транзакция третьего сеанса получила блокировку номера транзакции второго сеанса, доступ запрещён, ожидается завершение 760 тр-и.
   53434 | transactionid | 761      | ExclusiveLock    | t # Блокировка номера транзакции в режиме исключительной блокировки транзакцией третьего сеанса
   (5 rows)
   
   # Все блокировки, наложенные транзакцией первого сеанса сняты.
   
   locks=# SELECT pid, wait_event_type, wait_event, pg_blocking_pids(pid)
   FROM pg_stat_activity
   WHERE backend_type = 'client backend' ORDER BY pid;
   pid  | wait_event_type |  wait_event   | pg_blocking_pids
   -------+-----------------+---------------+------------------
   53413 | Client          | ClientRead    | {} 
   53422 | Client          | ClientRead    | {} # Второй сеанс разблокирован
   53434 | Lock            | transactionid | {53422} # Обновление третьего сеанса заблокировано транзакцией из второго сеанса
   53530 |                 |               | {}
   (4 rows)
    ```
   - 2 сеанс - применяем изменения:
    ```bash
   UPDATE 1 < -- после снятия блокиорвок транзакции из первого сеанса, второй сеанс получил возможность завершить обновление.
   locks=*# COMMIT;
   COMMIT
   locks=# < -- транзакция завершилась.
    ```
   - Контрольный сеанс:
    ```bash
   locks=# SELECT * FROM locks_v;
   pid  |   locktype    |  lockid  |       mode       | granted
   -------+---------------+----------+------------------+---------
   53434 | relation      | accounts | RowExclusiveLock | t # Остались только блокировка таблицы обновляемой строки транзакцией третьего сеанса, потому что транзакция не завершена,
   53434 | transactionid | 761      | ExclusiveLock    | t # и блокировка собственного номера транзакцией третьего сеанса
   (2 rows)
   
   locks=# SELECT pid, wait_event_type, wait_event, pg_blocking_pids(pid)
   FROM pg_stat_activity
   WHERE backend_type = 'client backend' ORDER BY pid;
   pid  | wait_event_type | wait_event | pg_blocking_pids
   -------+-----------------+------------+------------------
   53413 | Client          | ClientRead | {}
   53422 | Client          | ClientRead | {}
   53434 | Client          | ClientRead | {}
   53530 |                 |            | {}
   (4 rows)
   # Ни один сеанс больше не заблокирован.
    ```
   
   - 2 сеанс - применяем изменения::
    ```bash
   UPDATE 1 < -- после снятия блокиорвок транзакции из второго сеанса, третий сеанс получил возможность завершить обновление.
   locks=*# COMMIT;
   COMMIT
   locks=# < -- транзакция завершилась.
    ```
   - Контрольный сеанс:
    ```bash
   locks=# SELECT * FROM locks_v;
   pid | locktype | lockid | mode | granted
   -----+----------+--------+------+---------
   (0 rows)
   # Все блокировки сняты.
   
   locks=# SELECT pid, wait_event_type, wait_event, pg_blocking_pids(pid)
   FROM pg_stat_activity
   WHERE backend_type = 'client backend' ORDER BY pid;
   pid  | wait_event_type | wait_event | pg_blocking_pids
   -------+-----------------+------------+------------------
   53413 | Client          | ClientRead | {}
   53422 | Client          | ClientRead | {}
   53434 | Client          | ClientRead | {}
   53530 |                 |            | {}
   (4 rows)
    ```
   
3. Взаимная блокировка трех транзакций. В нашей таблице 3 счёта. Будем перечислять деньги между счетами:
с 1 на 2 перенесём 100, со 2 на 3 перенесём 200, с 3 на 1 перенесём 300.
   - 1 сеанс начнем транзакцию, спишем с 1 счета 100:
    ```bash
    locks=# BEGIN; 
    BEGIN
    locks=*# UPDATE accounts SET amount = amount - 100.00 WHERE acc_no  = 1;
    UPDATE 1 
     locks=*# < -- транзакция не завершена
    ```
   - 2 сеанс начнем транзакцию, спишем со 2 счета 200:
    ```bash
    locks=# BEGIN; 
    BEGIN
    locks=*# UPDATE accounts SET amount = amount - 200.00 WHERE acc_no  = 2;
    UPDATE 1 
     locks=*# < -- транзакция не завершена
    ```
   - 3 сеанс начнем транзакцию, спишем со 3 счета 300:
    ```bash
    locks=# BEGIN; 
    BEGIN
    locks=*# UPDATE accounts SET amount = amount - 300.00 WHERE acc_no  = 3;
    UPDATE 1 
     locks=*# < -- транзакция не завершена
    ```
   - 1 сеанс начислим на 2 счет 100:
    ```bash
    locks=*# UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 2; 
    < -- получили блокировку, потому что транзакция второго сеанса уже обновляет счет 2
    ```
   - 2 сеанс начислим на 3 счет 200:
    ```bash
    locks=*# UPDATE accounts SET amount = amount + 200.00 WHERE acc_no = 3; 
    < -- получили блокировку, потому что транзакция третьего сеанса уже обновляет счет 3
    ```
   - 3 сеанс начислим на счет 1 300:
    ```bash
    locks=*# UPDATE accounts SET amount = amount + 300.00 WHERE acc_no = 1;
      ERROR:  deadlock detected
      DETAIL:  Process 53434 waits for ShareLock on transaction 765; bloc ked by process 53413.
      Process 53413 waits for ShareLock on transaction 766; blocked by pr ocess 53422.
      Process 53422 waits for ShareLock on transaction 764; blocked by pr ocess 53434.
      HINT:  See server log for query details.
      CONTEXT:  while updating tuple (0,6) in relation "accounts"
      locks=!# < -- транзакция сломалась, лучше сделать откат.
    ```
   - 1 сеанс применяем изменения:
    ```bash
      locks=*# COMMIT;
      COMMIT
      locks=# 
    ```
   - 2 сеанс применяем изменения:
    ```bash
      locks=*# COMMIT;
      COMMIT
      locks=# 
    ```
   - 3 сеанс отменяем изменения:
    ```bash
      locks=!# ROLLBACK;
      ROLLBACK
      locks=#
    ```
   - Тем временем в сеансе просмотра лог-файла:
    ```bash
   devops0@otus-pg:~$ sudo tail -f /var/log/postgresql/postgresql-14-main.log
   ...
   2023-03-12 23:35:10.350 +05 [53422] postgres@locks STATEMENT:  UPDATE accounts SET amount = amount + 200.00 WHERE acc_no = 3;
   2023-03-12 23:35:23.902 +05 [53434] postgres@locks LOG:  process 53434 detected deadlock while waiting for ShareLock on transaction 765 after 200.213 ms
   2023-03-12 23:35:23.902 +05 [53434] postgres@locks DETAIL:  Process holding the lock: 53413. Wait queue: .
   2023-03-12 23:35:23.902 +05 [53434] postgres@locks CONTEXT:  while updating tuple (0,6) in relation "accounts"
   2023-03-12 23:35:23.902 +05 [53434] postgres@locks STATEMENT:  UPDATE accounts SET amount = amount + 300.00 WHERE acc_no = 1;
   
   # Получаем ошибку при попытке зачисления денег на 1 счёт.
   2023-03-12 23:35:23.902 +05 [53434] postgres@locks ERROR:  deadlock detected
   # Третий сеанс при попытке обновить 1 счет получил блокировку от транзакции из первого сеанса, в то время, как первый сеанс ждал завершения транзакции второго сеанса, а
   # второй не мог завершится, потому что должен был "зачислить" на 3 счёт деньги, а строка 3-его счета была заблокирована транзакцией третьего сеанса (списание перед зачислением на 1 счет).
   2023-03-12 23:35:23.902 +05 [53434] postgres@locks DETAIL:  Process 53434 waits for ShareLock on transaction 765; blocked by process 53413.
       Process 53413 waits for ShareLock on transaction 766; blocked by process 53422.
       Process 53422 waits for ShareLock on transaction 764; blocked by process 53434.
       Process 53434: UPDATE accounts SET amount = amount + 300.00 WHERE acc_no = 1;
       Process 53413: UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 2;
       Process 53422: UPDATE accounts SET amount = amount + 200.00 WHERE acc_no = 3;
   2023-03-12 23:35:23.902 +05 [53434] postgres@locks HINT:  See server log for query details.
   2023-03-12 23:35:23.902 +05 [53434] postgres@locks CONTEXT:  while updating tuple (0,6) in relation "accounts"
   2023-03-12 23:35:23.902 +05 [53434] postgres@locks STATEMENT:  UPDATE accounts SET amount = amount + 300.00 WHERE acc_no = 1;
   2023-03-12 23:35:23.904 +05 [53422] postgres@locks LOG:  process 53422 acquired ShareLock on transaction 764 after 13753.610 ms
   2023-03-12 23:35:23.904 +05 [53422] postgres@locks CONTEXT:  while updating tuple (0,3) in relation "accounts"
   2023-03-12 23:35:23.904 +05 [53422] postgres@locks STATEMENT:  UPDATE accounts SET amount = amount + 200.00 WHERE acc_no = 3;
   2023-03-12 23:36:48.715 +05 [53413] postgres@locks LOG:  process 53413 acquired ShareLock on transaction 766 after 130804.783 ms
   2023-03-12 23:36:48.715 +05 [53413] postgres@locks CONTEXT:  while updating tuple (0,2) in relation "accounts"
   2023-03-12 23:36:48.715 +05 [53413] postgres@locks STATEMENT:  UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 2;
    ```

4. Обновление строк командой UPDATE происходит построчно, порядок обновления строк зависит от структуры таблицы и индексов.
Обновляя таблицу в двух транзакциях командой UPDATE без фильтра WHERE можно получить блокировку этих двух
транзакций, когда они "сойдутся" на одной строке.

(*) Запуская команды по очереди в двух сеансах, не завершая транзакции первой - 
начиная вторую, блокировки получить не удалось. Транзакции "друг за другом" обновляют строки.
Появилась мысль, что нужно управлять порядком обновления строк. Так как
ORDER BY невозможно применить с операцией обновления, было решено искать решение в сети. По информации из статьи излюбленного
ресурса (https://stackoverflow.com/questions/44660368/postgres-update-with-order-by-how-to-do-it) получена ссылка на *курсоры*.

Мы можем создать курсор, в который инкапсулируем выборку обновляемых строк, затем получим ссылку на курсор и через цикл
получим из него строки, которые будем обновлять (команда DO позволит выполнить любой анонимный блок кода).
  - 1 сеанс:
    ```bash
      locks=# BEGIN;
      locks=*# DO $$DECLARE crsr CURSOR FOR SELECT acc_no, amount FROM accounts ORDER BY acc_no ASC FOR UPDATE;
      BEGIN
        FOR row IN crsr LOOP
          UPDATE accounts
          SET amount = 0
          WHERE CURRENT OF crsr;
        END LOOP;
      END$$;
      DO
      locks=*#
    ```
  - 2 сеанс:
    ```bash
      locks=# BEGIN;
      locks=*# DO $$DECLARE crsr CURSOR FOR SELECT acc_no, amount FROM accounts ORDER BY acc_no DESC FOR UPDATE;
      BEGIN
        FOR row IN crsr LOOP
          UPDATE accounts
          SET amount = 0
          WHERE CURRENT OF crsr;
        END LOOP;
      END$$;
      < -- блокировка
    ```
    
    - 1 сеанс:
     ```bash
      locks=*# COMMIT;
      COMMIT
      locks=#    
    ```
    
    - 2 сеанс:
     ```bash
      DO < -- разблокировка
      locks=*# COMMIT;
      COMMIT
      locks=#
    ```
    
    - Сеанс вывода лога:
     ```bash
      devops0@otus-pg:~$ sudo tail -f /var/log/postgresql/postgresql-14-main.log
      ...
      2023-03-13 00:13:40.398 +05 [53422] postgres@locks LOG:  process 53422 still waiting for ShareLock on transaction 771 after 200.228 ms
      2023-03-13 00:13:40.398 +05 [53422] postgres@locks DETAIL:  Process holding the lock: 53413. Wait queue: 53422.
      2023-03-13 00:13:40.398 +05 [53422] postgres@locks CONTEXT:  while locking tuple (0,33) in relation "accounts"
          PL/pgSQL function inline_code_block line 3 at FOR over cursor
      2023-03-13 00:13:40.398 +05 [53422] postgres@locks STATEMENT:  DO $$DECLARE crsr CURSOR FOR SELECT acc_no, amount FROM accounts ORDER BY acc_no DESC FOR UPDATE;
          BEGIN
            FOR row IN crsr LOOP
              UPDATE accounts
              SET amount = 0
              WHERE CURRENT OF crsr;
            END LOOP;
          END$$;
      2023-03-13 00:13:56.838 +05 [53422] postgres@locks LOG:  process 53422 acquired ShareLock on transaction 771 after 16640.612 ms
      2023-03-13 00:13:56.838 +05 [53422] postgres@locks CONTEXT:  while locking tuple (0,33) in relation "accounts"
          PL/pgSQL function inline_code_block line 3 at FOR over cursor
      2023-03-13 00:13:56.838 +05 [53422] postgres@locks STATEMENT:  DO $$DECLARE crsr CURSOR FOR SELECT acc_no, amount FROM accounts ORDER BY acc_no DESC FOR UPDATE;
          BEGIN
            FOR row IN crsr LOOP
              UPDATE accounts
              SET amount = 0
              WHERE CURRENT OF crsr;
            END LOOP;
          END$$;  
    ```