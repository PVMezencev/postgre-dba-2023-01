## Физический уровень PostgreSQL.

1. Создаём ВМ на ЯО:
    - Имя: "otus-pg"
    - Зона доступности: (по умолчанию) ru-central1-b
    - ОС: Ubuntu 20.04
    - vCPU: 2
    - RAM: 4 ГБ
    - Логин: (придумываем) devops0
    - SSH-ключ: получаем публичный ключ со своей рабочей машины, в моём случе это: `cat ~/.ssh/id_rsa.pub`, копируем строку, как рекомендует поле в админ-панели ЯО.
2. Устанавливаем PostgreSQL 14 через sudo apt:
    - Обновим систему: `sudo apt -y update && sudo apt dist-upgrade`
    - По умолчанию в репозиториях Ubuntu 20.04 недоступна 14-я версия, по этому добавим репозиторий и импортируем его публичный ключ. `sudo apt -y install gnupg2 wget && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -`
    - Выполним обновление списка репозиториев: `sudo apt -y update` и получим информационное предупреждение о том, что репозиторий PostgreSQL не поддерживает i386 архитектуру. Чтоб избавиться от этого предупреждения отредактируем файл `sudo nano /etc/apt/sources.list.d/pgdg.list` - укажем явно `deb [arch=amd64] http://apt.postgresql.org/pub/repos/apt focal-pgdg main` вместо `deb http://apt.postgresql.org/pub/repos/apt focal-pgdg main`.
    - Предупреждение больше не беспокоит. Устанавливаем PostgreSQL `sudo apt -y install postgresql-14`
3. Проверим, что кластер установился и работает: `sudo -u postgres pg_lsclusters`:

```bash
devops0@otus-pg:~$ sudo -u postgres pg_lsclusters
Ver Cluster Port Status Owner    Data directory    Log file
14  main    5432 online postgres /mnt/data/14/main /var/log/postgresql/postgresql-14-main.log
```
4. Создадим простые демонстрационные данные:
    - Запускаем оболочку bash под пользователем postgres: `sudo -u postgres -i`
    - Запускаем `psql`
    - Выполняем команду создания таблицы: `postgres=# create table test(c1 text);`
    - Выполняем команду заполнения таблицы: `postgres=# insert into test values('1');`
    - Выполняем команду завершения psql: `postgres=# \q`
    - Завершаем сеанс пользователя postgres сочетанием клавиш Ctrl+D (можно ввести `exit` и нажать Enter)
5. Остановим работу кластера `sudo -u postgres pg_ctlcluster 14 main stop`
6. Создадим внешний диск на ЯО, примонтируем его к ВМ:
    - Имя: "otus-pg-hdd"
    - Зона доступности: (по умолчанию) ru-central1-b
    - Размер: 10 ГБ
7. Присоединим созданный диск к ВМ: через меню выбираем "Присоединить", выбираем ВМ, снимаем галочку "Автоматическое удаление", жмём "Подключить".
8. Инициализируем диск:
    - Устанавливаем утилиту для работы с ФС: `sudo apt install parted`
    - Определяем путь к присоединённому диску: `lsblk` -> в нашем случе это /dev/vdb
    - Создадим новую таблицу разделов на новом диске: `sudo parted /dev/vdb mklabel msdos`
    - Создадим новый раздел на диске: `sudo parted -a opt /dev/vdb mkpart primary ext4 0% 100%`. После этого команда `lsblk` покажет, что появился новый раздел /dev/vdb1
    - Форматируем раздел в файловую систему ext4: `sudo mkfs.ext4 -L datapartition /dev/vdb1`
    - Мы указали метку тома datapartition, проверим: `sudo lsblk --fs`:
    ```bash
    devops0@otus-pg:~$ sudo lsblk --fs
    NAME   FSTYPE LABEL         UUID                                 FSAVAIL FSUSE% MOUNTPOINT
    vda                                                                             
    ├─vda1                                                                          
    └─vda2 ext4                 be2c7c06-cc2b-4d4b-96c6-e3700932b129   10.9G    21% /
    vdb                                                                             
    └─vdb1 ext4   datapartition 2a0c4633-23ed-4f81-9475-177052ba130c
   ```
    - Примонтируем диск в ФС нашей ВМ, для этого сначала создадим место, куда будем монтировать (точку монтирования): `sudo mkdir -p /mnt/data`
    - Добавим строку в /etc/fstab, чтоб диск монтировался при старте системы: `sudo nano /etc/fstab`
    ```bash
    LABEL=datapartition /mnt/data ext4 defaults 0 2
   ```
    - Сохраним fstab, выполним команду, которая монтирует все точки, настроенные в этом файле `sudo mount -a`
9. Перезагружаем ВМ, убеждаемся, что диск примонтировался: `sudo reboot`, `df -h -x tmpfs`
    ```bash
    devops0@otus-pg:~$ df -h -x tmpfs
    Filesystem      Size  Used Avail Use% Mounted on
    udev            1.9G     0  1.9G   0% /dev
    /dev/vda2        15G  3.2G   11G  23% /
    /dev/vdb1       9.8G   42M  9.2G   1% /mnt/data
   ```
10. Для каталога, в который смонтирован диск, устанавливаем владельца postgres, чтоб процесс кластера имел доступ к данным на этом диске: `sudo chown -R postgres:postgres /mnt/data/`
11. Переносим все файлы данных кластера на внешний диск: `sudo -u postgres mv /var/lib/postgresql/14 /mnt/data`
12. При попытке запустить кластер `sudo -u postgres pg_ctlcluster 14 main start` получаем ошибку, которая сообщает нам, что не может найти каталог /var/lib/postgresql/14
13. Найдём конфигурационный файл, в котором задается путь до каталога с данными: `sudo grep -r "/var/lib/postgresql/14" /etc/postgresql/`
    ```bash
    devops0@otus-pg:~$ sudo grep -r "/var/lib/postgresql/14" /etc/postgresql/
    /etc/postgresql/14/main/postgresql.conf:# data_directory = '/var/lib/postgresql/14/main'		# use data in another directory   
    ```
    Нашли файл /etc/postgresql/14/main/postgresql.conf и параметр data_directory
14. Заменяем в этом файле data_directory = '/var/lib/postgresql/14/main' на data_directory = '/mnt/data/14/main', сохраняем его.
15. Запускаем кластер: `sudo -u postgres pg_ctlcluster 14 main start` - все стартует успешно, потому что процессу доступен каталог с данными на внешнем диске.
16. Проверим, на месте ли данные:
    - Запускаем оболочку bash под пользователем postgres: `sudo -u postgres -i`
    - Запускаем `psql`
    ```bash
      postgres=# select * from test;
      c1
      ----
      1
      (1 row)
      ```
    - Данные на месте. Закрываем консоль, завершаем сеанс пользователя postgres
17. Подключаем существующий внешний диск со всеми данными к новой ВМ (*):
    - Повторяем пункты 1 (только ВМ назовём "otus-pg2"), 2, 3.
    - Остановим кластер на ВМ otus-pg: `sudo -u postgres pg_ctlcluster 14 main stop`
    - Отмонтируем диск от ВМ otus-pg: `sudo umount /mnt/data`
    - Отключим диск от ВМ в панели управления ЯО: меню "..."-отсоединить
    - Далее работаем на новой ВМ otus-pg2
    - Подключим диск к новой ВМ otus-pg2 в панели управления ЯО аналогично п. 7
    - На диске осталась прежняя метка тома datapartition, проверим: `sudo lsblk --fs`:

    ```bash
        devops0@otus-pg2:~$ sudo lsblk --fs
        NAME   FSTYPE LABEL         UUID                                 FSAVAIL FSUSE% MOUNTPOINT
        vda                                                                             
        ├─vda1                                                                          
        └─vda2 ext4                 be2c7c06-cc2b-4d4b-96c6-e3700932b129   10.9G    21% /
        vdb                                                                             
        └─vdb1 ext4   datapartition 2a0c4633-23ed-4f81-9475-177052ba130c
    ```

    - Примонтируем диск в ФС нашей ВМ, для этого сначала создадим место, куда будем монтировать (точку монтирования): `sudo mkdir -p /mnt/data`
    - Добавим строку в /etc/fstab, чтоб диск монтировался при старте системы: `sudo nano /etc/fstab`

    ```bash
        LABEL=datapartition /mnt/data ext4 defaults 0 2
    ```
    - Сохраним fstab, выполним команду которая монтирует все точки, настроенные в этом файле `sudo mount -a`
    - Для каталога, в который смонтирован диск, устанавливаем владельца postgres, чтоб процесс кластера имел доступ к данным на этом диске: `sudo chown -R postgres:postgres /mnt/data/`
    - Удалим все файлы с данными из /var/lib/postgres
    - Заменяем в файле /etc/postgresql/14/main/postgresql.conf параметр data_directory = '/var/lib/postgresql/14/main' на data_directory = '/mnt/data/14/main', сохраняем его.
    - Повторяем пункти 15, 16 - всё работает.