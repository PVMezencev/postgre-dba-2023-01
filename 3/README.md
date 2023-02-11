## Установка PostgreSQL.

Будет использоваться виртуальный сервер на VDS-хостинге с выделенным IP адресом, ОС - Debian 11. Начальная подготовка ОС к работе была описана в [предыдущем задании](../2/README.md).

1. Устанавливаем Docker Engine по [официальной документации](https://docs.docker.com/engine/install/debian/):
   ```bash
   #  Обновим список репозиториев, обновим пакеты, удалим более не требуемые файлы.
   sudo apt update && sudo apt dist-upgrade -y && sudo apt autoremove -y
   # Установим необходимые утилиты (на всякий случай, если они не установлены ранее).
   sudo apt install ca-certificates curl gnupg lsb-release -y
   # Создадим каталог для хранения ключей внешних репозиториев.
   sudo mkdir -m 0755 -p /etc/apt/keyrings
   # Затем, нужно импортировать в систему публичный ключ репозитория.
   curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
   # Добавим репозиторий в систему.
   echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
   # Снова обновим список репозиториев.
   sudo apt update
   # И установим Docker Engine.
   sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
   # Для проверки докера официальная документация рекомендует выполнить следующую команду:
   sudo docker run hello-world
   # Должно получиться следующее:
   Unable to find image 'hello-world:latest' locally
   latest: Pulling from library/hello-world
   2db29710123e: Pull complete
   Digest: sha256:aa0cc8055b82dc2509bed2e19b275c8f463506616377219d9642221ab53cf9fe
   Status: Downloaded newer image for hello-world:latest
   
   Hello from Docker!
   This message shows that your installation appears to be working correctly.
   
   To generate this message, Docker took the following steps:
   1. The Docker client contacted the Docker daemon.
   2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (amd64)
   3. The Docker daemon created a new container from that image which runs the
    executable that produces the output you are currently reading.
   4. The Docker daemon streamed that output to the Docker client, which sent it
    to your terminal.
   
   To try something more ambitious, you can run an Ubuntu container with:
   $ docker run -it ubuntu bash
   
   Share images, automate workflows, and more with a free Docker ID:
   https://hub.docker.com/
   
   For more examples and ideas, visit:
   https://docs.docker.com/get-started/
   
   # Для просмотра списка запущенных контейнеров используем команду:
   sudo docker ps
   # Получаем:
   CONTAINER ID   IMAGE         COMMAND    CREATED          STATUS                      PORTS     NAMES
   # Ничего нет, потому что hello-world выполнился и выключился автоматически.
   # Чтоб увидеть все контейнеры, нужно добавить флаг -a:
   sudo docker ps -a
   # Получаем:
   CONTAINER ID   IMAGE         COMMAND    CREATED          STATUS                      PORTS     NAMES
   6bb8e1dab844   hello-world   "/hello"   19 minutes ago   Exited (0) 19 minutes ago             adoring_cannon
   ```
2. Создадим каталог для хранения данных (баз данных кластера, который будет работать в контейнере):
    ```bash
   sudo mkdir -p /var/lib/postgres/
    ```
3. Скачаем образ докера с postgres 14 из их репозитория:
    ```bash
   sudo docker pull postgres:14
    # Получаем:
   14: Pulling from library/postgres
    bb263680fed1: Already exists
    75a54e59e691: Already exists
    3ce7f8df2b36: Already exists
    f30287ef02b9: Already exists
    dc1f0e9024d8: Already exists
    7f0a68628bce: Already exists
    32b11818cae3: Already exists
    48111fe612c1: Already exists
    804b23d51438: Pull complete
    c3d377381b80: Pull complete
    3bdba78b9445: Pull complete
    cfca31b73d7d: Pull complete
    4587f867eece: Pull complete
    Digest: sha256:f565573d74aedc9b218e1d191b04ec75bdd50c33b2d44d91bcd3db5f2fcea647
    Status: Downloaded newer image for postgres:14
    docker.io/library/postgres:14
    ```
4. Создадим сеть для контейнеров докера:
    ```bash
   sudo docker network create pg-net
    ```
5. Создадим и запустим контейнер с postgres:
    ```bash
   sudo docker run --name pg-server --network pg-net -e POSTGRES_PASSWORD=postgres -d -p 5432:5432 -v /var/lib/postgres:/var/lib/postgresql/data postgres:14
    # Получаем:
    1610e12e1b253892f83eee8456e1e22f4b48a2559eccf6cada957c48a0697d72
    docker: Error response from daemon: driver failed programming external connectivity on endpoint pg-server (7804ff9cc32353b6ce8ea23f9cfc6a7d05cec541ab86dfb35e09231083d18f69): Error starting userland proxy: listen tcp4 0.0.0.0:5432: bind: address already in use.
    # Потому что 5432 порт уже чем-то занят, проверим, кто его занял:
   sudo ss -lptn 'sport = :5432'
   # Видим, что порт 5432 занимает кластер postgres:
   State               Recv-Q              Send-Q                           Local Address:Port                             Peer Address:Port              Process                                            
    LISTEN              0                   244                                  127.0.0.1:5432                                  0.0.0.0:*                  users:(("postgres",pid=101414,fd=6))              
    LISTEN              0                   244                                      [::1]:5432                                     [::]:*                  users:(("postgres",pid=101414,fd=5))
    # Потому что у нас работает кластер postgres 15 с прошлого ДЗ:
    pg_lsclusters
    # 
    Ver Cluster Port Status Owner    Data directory              Log file
    15  main    5432 online postgres /var/lib/postgresql/15/main /var/log/postgresql/postgresql-15-main.log

    # Выключим его (но можно и изменить порт для контейнера):
    sudo pg_ctlcluster 15 main stop
    # Проверим:
    pg_lsclusters
    # Кластер выключен: 
    Ver Cluster Port Status Owner    Data directory              Log file
    15  main    5432 down   postgres /var/lib/postgresql/15/main /var/log/postgresql/postgresql-15-main.log

   # Пытаемся запустить контейнер ещё раз: 
   sudo docker run --name pg-server --network pg-net -e POSTGRES_PASSWORD=postgres -d -p 5432:5432 -v /var/lib/postgres:/var/lib/postgresql/data postgres:14
    # Получаем:
    docker: Error response from daemon: Conflict. The container name "/pg-server" is already in use by container "1610e12e1b253892f83eee8456e1e22f4b48a2559eccf6cada957c48a0697d72". You have to remove (or rename) that container to be able to reuse that name.
    See 'docker run --help'.
    # Потому что с предыдущей попытки у нас контейнер создался, но не смог запуститься из-за занятого порта:
   sudo docker ps -a
   # Видим контейнер со статусом "Created":
    CONTAINER ID   IMAGE         COMMAND                  CREATED         STATUS                    PORTS     NAMES
    1610e12e1b25   postgres:14   "docker-entrypoint.s…"   8 minutes ago   Created                             pg-server
    6bb8e1dab844   hello-world   "/hello"                 15 hours ago    Exited (0) 15 hours ago             adoring_cannon
    # Просто запустим созданный контейнер:
   sudo docker start pg-server
   # Проверим:
   sudo docker ps
   # Видим контейнер со статусом "Up About a minute":
    CONTAINER ID   IMAGE         COMMAND                  CREATED          STATUS              PORTS                                       NAMES
    1610e12e1b25   postgres:14   "docker-entrypoint.s…"   13 minutes ago   Up About a minute   0.0.0.0:5432->5432/tcp, :::5432->5432/tcp   pg-server
    ```
6. Создадим контейнер с клиентом postgres и подключимся из него к контейнеру с кластером postgres:
    ```bash
    sudo docker run -it --rm --network pg-net --name pg-client postgres:14 psql -h pg-server -U postgres
    Password for user postgres: # Потребуется ввести пароль, указанный в переменной окружения POSTGRES_PASSWORD при создании контейнера с кластером.
    psql (14.6 (Debian 14.6-1.pgdg110+1))
    Type "help" for help.
    
    postgres=#
   
    # Возьмем пример из предыдущего ДЗ и создадим таблицу с парой строк:
    postgres=# create table persons(id serial, first_name text, second_name text); insert into persons(first_name, second_name) values('ivan', 'ivanov'); insert into persons(first_name, second_name) values('petr', 'petrov');
    # Проверим:
   postgres=# select * from persons;
    # Данные записались:
   id | first_name | second_name 
   ----+------------+-------------
   1 | ivan       | ivanov
   2 | petr       | petrov
   (2 rows)

    # Отключимся (при этом, контейнер удалится, потому что при его запуске мы указали опцию --rm):
   postgres=# \q
    ```
7. Подключимся к контейнеру с кластером (напомню, он у нас на внешнем VDS в интернете) с рабочего компьютера (Ubuntu 22.04) по ip адресу VDS:
    ```bash
   psql -h IP_ADDRESS -p 5432 -U postgres
   # Успех!
   Password for user postgres: # Потребуется ввести пароль, указанный в переменной окружения POSTGRES_PASSWORD при создании контейнера с кластером.
   psql (14.6 (Ubuntu 14.6-0ubuntu0.22.04.1))
   Type "help" for help.
   
   # Выполним выборку для проверки:  
   postgres=# select * from persons;
   id | first_name | second_name
   ----+------------+-------------
   1 | ivan       | ivanov
   2 | petr       | petrov
   (2 rows)
   
   # Отключаемся:
   postgres-# \q
    ```
8. Удалим контейнер с кластером postgres:
    ```bash
   # Сначала остановим:
   sudo docker stop pg-server
   # Затем удаляем:
   sudo docker rm pg-server
   # Затем проверяем:
   sudo docker ps -a
   # Видим, что контейнера нет:
   CONTAINER ID   IMAGE         COMMAND    CREATED        STATUS                    PORTS     NAMES
   6bb8e1dab844   hello-world   "/hello"   16 hours ago   Exited (0) 16 hours ago             adoring_cannon
    ```
9. Создадим контейнер заново (просто повторим команду):
    ```bash
   sudo docker run --name pg-server --network pg-net -e POSTGRES_PASSWORD=postgres -d -p 5432:5432 -v /var/lib/postgres:/var/lib/postgresql/data postgres:14
   # Затем проверяем:
   sudo docker ps -a
   # Видим, что контейнер появился и запущен:
   CONTAINER ID   IMAGE         COMMAND                  CREATED         STATUS                    PORTS                                       NAMES
   c0a6b48034ff   postgres:14   "docker-entrypoint.s…"   6 seconds ago   Up 5 seconds              0.0.0.0:5432->5432/tcp, :::5432->5432/tcp   pg-server
   6bb8e1dab844   hello-world   "/hello"                 16 hours ago    Exited (0) 16 hours ago                                               adoring_cannon
    ```
11. Создадим контейнер с клиентом postgres и подключимся из него к контейнеру с кластером postgres:
     ```bash
     sudo docker run -it --rm --network pg-net --name pg-client postgres:14 psql -h pg-server -U postgres
     Password for user postgres: # Потребуется ввести пароль, указанный в переменной окружения POSTGRES_PASSWORD при создании контейнера с кластером.
     psql (14.6 (Debian 14.6-1.pgdg110+1))
     Type "help" for help.
    
     postgres=#
     ```
12. Проверим, что после пересоздания контейнера с кластером данные не потерялись:
     ```bash
     # Выполним запрос:
    postgres=# select * from persons;
     # Данные на месте, потому что мы примонтировали папку на хостовой машине /var/lib/postgres к папке контейнера /var/lib/postgresql/data:
    id | first_name | second_name 
    ----+------------+-------------
    1 | ivan       | ivanov
    2 | petr       | petrov
    (2 rows)

     # Отключимся (при этом, контейнер удалится, потому что при его запуске мы указали опцию --rm):
    postgres=# \q
     ```

Использовались материалы из лекций, а так же интернет ресурсы:

Официальный сайт докера: https://docs.docker.com/engine/install/debian/

Мануал по запуску postgres у хостера Selectel: https://selectel.ru/blog/postgresql-docker-setup/