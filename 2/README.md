## SQL и реляционные СУБД. Введение в PostgreSQL.

Будет использоваться виртуальный сервер на VDS-хостинге с выделенным IP адресом, ОС - Debian 11.
1. Подключаемся под учетными данными, выданными хостером (пользователь root), первым делом обновляем систему, установим вспомогательные утилиты:
    ```bash
     apt update && apt dist-upgrade -y && apt install sudo wget software-properties-common apt-transport-https gnupg gnupg2 curl -y
    ```
2. Меняем порт сервиса SSH (для повышения безопасности) со стандартного на любой:
    ```bash
   nano /etc/ssh/sshd_config
    ```
   Меняем `Port 22`, например на `Port 61467`, CTRL+O - сохранить, CTRL+X - выйти.
3. Добавим пользователя, от которого будем работать:
    ```bash
    adduser devops0
    ```
4. Добавим пользователя в группу sudo, чтоб он мог выполнять команды через sudo:
    ```bash
    usermod -aG sudo devops0
    ```
5. Установим пользователю пароль:
    ```bash
    passwd devops0
    ```
   дважды потребуется ввести пароль, при этом, вводимые символы не будут отображаться.
6. Проверим параметры пользователя:
    ```bash
    id devops0
   # должно получиться примерно следующее:
   uid=1000(devops0) gid=1000(devops0) groups=1000(devops0),27(sudo)
    ```
7. Перезапускаем службу SSH (чтоб применился изменённый порт) и отключаемся от сервера:
    ```bash
   service ssh restart
    ```
8. На рабочей машине создаём конфиг для быстрого подключения к серверу:
    ```bash
   cd ~ && nano .ssh/config
    ```
   добавляем примерно следующее:
    ```bash
   Host pghost
        HostName ip-адрес
        Port 61467
        User devops0
    ```
   CTRL+O - сохранить, CTRL+X - выйти.
9. Генерируем себе SSH ключ для подключения к серверу, просто нажимаем Enter (ВНИМАНИЕ! Если у вас уже есть ключ, утилита спросит, перезаписать ли его):
    ```bash
   ssh-keygen
    ```
   получится примерно следующее:
    ```bash
    Generating public/private rsa key pair.
    Enter file in which to save the key (/home/devops0/.ssh/id_rsa):
    /home/devops0/.ssh/id_rsa already exists.
    Overwrite (y/n)? y # тут я перезаписал файлы ключей
    Enter passphrase (empty for no passphrase):
    Enter same passphrase again:
    Your identification has been saved in /home/devops0/.ssh/id_rsa
    Your public key has been saved in /home/devops0/.ssh/id_rsa.pub
    The key fingerprint is:
    SHA256:oNVaEtnXVzhVMTKrUAxE6XQdyNpEbnVh9Jcxu8lbwZ4 devops0@pghost
    The key's randomart image is:
    +---[RSA 3072]----+
    |      .oo+*+o=o&B|
    |      .o.o+*o.@ B|
    |      + =o=o o *o|
    |     o = oo.. o *|
    |    . . S  .   E.|
    |                o|
    |               . |
    |                 |
    |                 |
    +----[SHA256]-----+
   ```
10. Отправим свой ключ на сервер:
     ```bash
    ssh-copy-id pghost
     ```
    потребуется ввести пароль пользователя. Далее, мы уже сможем подключаться к серверу без ввода пароля по имени хоста:
     ```bash
    ssh pghost
     ```
    #### Рекомендуется в настройках сервера SSH запретить доступ пользователю root, и отключить авторизацию по паролю - только ssh-ключ.
11. Подключимся к серверу:
     ```bash
    ssh pghost
     ```
12. Устанавливаем postgres (теперь нужно использовать утилиту sudo для повышения привилегий на команду и вводить свой пароль). Для начала нужно добавить репозиторий в систему:
     ```bash
    echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt/ bullseye-pgdg main" | sudo tee /etc/apt/sources.list.d/postgresql.list
     ```
13. Затем, нужно импортировать в систему публичный ключ репозитория:
     ```bash
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg
     ```
14. Затем, наконец-то, устанавливаем postgres (на момент написания 15 версия самая новая):
     ```bash
    sudo apt install postgresql-15 -y
     ```
15. Теперь включим postgres, добавим в автозагрузку и сразу проверим состояние:
     ```bash
    sudo systemctl start postgresql 
     ```
     ```bash
    sudo systemctl enable postgresql
     ```
     ```bash
    sudo systemctl status postgresql
     ```
    получится примерно следующее:
     ```bash
    ● postgresql.service - PostgreSQL RDBMS
    Loaded: loaded (/lib/systemd/system/postgresql.service; enabled; vendor preset: enabled)
    Active: active (exited) since Thu 2023-02-09 15:32:52 +05; 1min 13s ago
    Main PID: 77040 (code=exited, status=0/SUCCESS)
    Tasks: 0 (limit: 2335)
    Memory: 0B
    CPU: 0
    CGroup: /system.slice/postgresql.service
    
    фев 09 15:32:52 pghost systemd[1]: Starting PostgreSQL RDBMS...
    фев 09 15:32:52 pghost systemd[1]: Finished PostgreSQL RDBMS.
     ```
11. Авторизуемся под пользователем postgres (он создается автоматически при установке postgres):
     ```bash
    sudo -i -u postgres
     ```
11. Запустим утилиту управления postgres через командную строку:
     ```bash
    psql
     ```
11. Подключимся к серверу второй сессией, повторим предыдущие шаги:
     ```bash
    ssh pghost
     ```
     ```bash
    sudo -i -u postgres
     ```
     ```bash
    psql
     ```
11. В первой и во второй сессии выключаем auto commit:
     ```bash
    postgres-# \set AUTOCOMMIT off
     ```
11. Сделаем в первой сессии новую таблицу и наполняем ее данными:
     ```bash
    postgres-# create table persons(id serial, first_name text, second_name text); insert into persons(first_name, second_name) values('ivan', 'ivanov'); insert into persons(first_name, second_name) values('petr', 'petrov'); commit;
     ```
    результат:
     ```bash
    CREATE TABLE
    INSERT 0 1
    INSERT 0 1
    COMMIT
     ```
11. Посмотрим текущий уровень изоляции:
     ```bash
    postgres=# show transaction isolation level;
     ```
    результат:
     ```bash
    transaction_isolation
    -----------------------
    read committed
    (1 row)
     ```
11. Начнём новую транзакцию в обеих сессиях с дефолтным (не меняя) уровнем изоляции:
     ```bash
    postgres=*# begin;
     ```
    результат первой сессии:
     ```bash
    WARNING:  there is already a transaction in progress
    BEGIN
     ```
    результат второй сессии:
     ```bash
    BEGIN
     ```
11. В первой сессии добавим новую запись:
     ```bash
    postgres=*# insert into persons(first_name, second_name) values('sergey', 'sergeev');
     ```
    результат:
     ```bash
    INSERT 0 1
     ```
11. Сделаем выборку во второй сессии:
     ```bash
    postgres=*# select * from persons;
     ```
    в результате новая запись пока не видна, потому что транзакция первой сессии не завершена (уровень изоляции транзакций "read committed" не позволяет видеть незафиксированные изменения параллельных транзакций):
     ```bash
    id | first_name | second_name
    ----+------------+-------------
    1 | ivan       | ivanov
    2 | petr       | petrov
    (2 rows)
     ```
11. Завершаем транзакцию в первой сессии:
     ```bash
    postgres=*# commit;
     ```
    результат:
     ```bash
    COMMIT
     ```
11. Сделаем выборку во второй сессии:
     ```bash
    postgres=*# select * from persons;
     ```
    в результате появилась новая запись, потому что успешно завершилась транзакция первой сессии (уровень изоляции транзакций "read committed" видит данные, которые были зафиксированы до начала запроса):
     ```bash
    id | first_name | second_name
    ----+------------+-------------
    1 | ivan       | ivanov
    2 | petr       | petrov
    3 | sergey     | sergeev
    (3 rows)
     ```
11. Завершаем транзакцию во второй сессии:
     ```bash
    postgres=*# commit;
     ```
    результат:
     ```bash
    COMMIT
     ```
11. Начнём новые транзакции в обеих сессиях, но уже с уровнем изоляции транзакции "repeatable read":
     ```bash
    postgres=# set transaction isolation level repeatable read;
     ```
    результат:
     ```bash
    SET
     ```
    _после выполнения команды set transaction isolation level repeatable read; автоматически началась новая транзакция._
11. В первой сессии добавим новую запись:
     ```bash
    postgres=*# insert into persons(first_name, second_name) values('sveta', 'svetova');
     ```
    результат:
     ```bash
    INSERT 0 1
     ```
11. Сделаем выборку во второй сессии:
     ```bash
    postgres=*# select * from persons;
     ```
    в результате новая запись не появилась (в режиме изоляции транзации "repeatable read" видны только те данные, которые были зафиксированы до начала транзакции):
     ```bash
    id | first_name | second_name
    ----+------------+-------------
    1 | ivan       | ivanov
    2 | petr       | petrov
    3 | sergey     | sergeev
    (3 rows)
     ```
11. Завершаем транзакцию в первой сессии:
     ```bash
    postgres=*# commit;
     ```
    результат:
     ```bash
    COMMIT
     ```
11. Сделаем выборку во второй сессии:
     ```bash
    postgres=*# select * from persons;
     ```
    в результате новая запись не появилась (мы ещё не завершили текущую транзакцию в режиме изоляции "repeatable read"):
     ```bash
    id | first_name | second_name
    ----+------------+-------------
    1 | ivan       | ivanov
    2 | petr       | petrov
    3 | sergey     | sergeev
    (3 rows)
     ```
11. Завершаем транзакцию во второй сессии:
     ```bash
    postgres=*# commit;
     ```
    результат:
     ```bash
    COMMIT
     ```
11. Сделаем выборку во второй сессии:
     ```bash
    postgres=# select * from persons;
     ```
    в результате появилась новая запись, потому что мы завершили текущую транзакцию, стали доступны завфиксированные изменения, произведенные параллельной транзакцией первой сессии:
     ```bash
    id | first_name | second_name
    ----+------------+-------------
    1 | ivan       | ivanov
    2 | petr       | petrov
    3 | sergey     | sergeev
    4 | sveta      | svetova
    (4 rows)
     ```


   