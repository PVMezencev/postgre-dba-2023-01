## Установка PostgreSQL.

Будет использоваться виртуальный сервер на VDS-хостинге с выделенным IP адресом, ОС - Debian 11. Начальная подготовка ОС к работе была описана в [предыдущем задании](../2/README.md).

1. Устанавливаем Docker Engine по [официальной документации](https://docs.docker.com/engine/install/debian/):
  ```bash
  #  Обновим список репозиториев, обновим пакеты, удалим более не требуемые файлы.
  sudo apt update && apt dist-upgrade -y && apt autoremove -y
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
  # И, наконец-то, установим Docker Engine.
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
  #
  ```