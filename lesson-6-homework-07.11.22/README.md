
## Подготавливаем окружение
- Создал машинку в YC via TF. Через user-data прокинул публичный ключ.
  ```bash
  sudo apt update && \
    sudo apt -y install gnupg2 wget vim && \
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && \
    sudo apt -y update && \
    sudo apt install postgresql-14 -y
  ```

- Проверяем, что кластер установился:
  ```bash
  root@fhm1jeb25jmrdsf1qog4:~# pg_lsclusters
  Ver Cluster Port Status Owner    Data directory              Log file
  14  main    5432 online postgres /var/lib/postgresql/14/main /var/log/postgresql/postgresql-14-main.log
  ```

- Добавляем произвольные данные:
  ```sql
  root@fhm1jeb25jmrdsf1qog4:~# su postgres
  postgres@fhm1jeb25jmrdsf1qog4:/root$ psql
  could not change directory to "/root": Permission denied
  psql (14.5 (Debian 14.5-2.pgdg100+2))
  Type "help" for help.

  postgres=# create table test(c1 text);
  CREATE TABLE
  postgres=#  insert into test values('1');
  INSERT 0 1
  postgres=#
  ```

- Инициализируем заранее созданный диск
  Устанавливаем parted:
  ```bash
  root@fhm1jeb25jmrdsf1qog4:~# apt-get install parted -y
  ```
- Задаём стандарт партиций и создаём партицию:
  ```bash
  root@fhm1jeb25jmrdsf1qog4:~# parted /dev/vdb mklabel gpt
  root@fhm1jeb25jmrdsf1qog4:~# sudo parted -a opt /dev/vdb mkpart primary ext4 0% 100%
  ```
- parted любезно напоминает нам о том, что нам нужно обновить наш fstab: ```Information: You may need to update /etc/fstab.```

- Видим, что новая партиция создалась:
  ```bash
  root@fhm1jeb25jmrdsf1qog4:~# lsblk
  NAME   MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
  vda    254:0    0  50G  0 disk
  ├─vda1 254:1    0   1M  0 part
  └─vda2 254:2    0  50G  0 part /
  vdb    254:16   0  50G  0 disk
  └─vdb1 254:17   0  50G  0 part
  ```

- Создаём директорию ```mkdir -p /mnt/data```, устанавливаем файловую систему ```sudo mkfs.ext4 -L /data /dev/vdb1``` и добавляем в наш ```/etc/fstab```: ```/dev/vdb1 /data ext4 error=remout-ro 0 1``` Выполняем ```sudo mount -a```
  ```bash
  root@fhm1jeb25jmrdsf1qog4:~# lsblk
  NAME   MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
  vda    254:0    0  50G  0 disk
  ├─vda1 254:1    0   1M  0 part
  └─vda2 254:2    0  50G  0 part /
  vdb    254:16   0  50G  0 disk
  └─vdb1 254:17   0  50G  0 part /mnt/data
  ```
- Видим, что к директории /mnt/data примонтирован наш второй диск.

## Перенос данных

- Меняем владельца нашей директории:
  ```bash
  chown -R postgres:postgres /mnt/data/
  ```
- Переносим данные и пробуем запустить кластер
  ```bash
  mv /var/lib/postgresql/14 /mnt/data
  root@fhm1jeb25jmrdsf1qog4:~# pg_ctlcluster 14 main start
  Error: /var/lib/postgresql/14/main is not accessible or does not exist
  ```
  Получаем ошибку, которая говорит нам о том, что служба Postgres'а не находит кластер. Чтобы это исправить нам нужно исправить параметр ```data_directory``` в конфигурационном файле ```/etc/postgresl/14/main/postgrtesql.conf```.  ```data_directory = '/mnt/data/14/main'```
  Проверяем на месте ли наши данные:
  ```bash
  root@fhmkgau2oul1b3ui9trh:~# pg_lsclusters
  Ver Cluster Port Status Owner    Data directory    Log file
  14  main    5432 online postgres /mnt/data/14/main /var/log/postgresql/postgresql-14-main.log
  root@fhmkgau2oul1b3ui9trh:~# su postgres
  postgres@fhmkgau2oul1b3ui9trh:/root$ psql
  could not change directory to "/root": Permission denied
  psql (14.5 (Debian 14.5-2.pgdg100+2))
  Type "help" for help.
  ```
  ```sql
  postgres=# \l
                                    List of databases
    Name    |  Owner   | Encoding |   Collate   |    Ctype    |   Access privileges
  -----------+----------+----------+-------------+-------------+-----------------------
  postgres  | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
  template0 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
            |          |          |             |             | postgres=CTc/postgres
  template1 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
            |          |          |             |             | postgres=CTc/postgres
  (3 rows)

  postgres=# \c postgres
  You are now connected to database "postgres" as user "postgres".
  postgres=# \l
                                    List of databases
    Name    |  Owner   | Encoding |   Collate   |    Ctype    |   Access privileges
  -----------+----------+----------+-------------+-------------+-----------------------
  postgres  | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
  template0 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
            |          |          |             |             | postgres=CTc/postgres
  template1 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
            |          |          |             |             | postgres=CTc/postgres
  (3 rows)

  postgres=# \d
          List of relations
  Schema | Name | Type  |  Owner
  --------+------+-------+----------
  public | test | table | postgres
  (1 row)

  postgres=# select * from test;
  c1
  ----
  1
  (1 row)
  ```

## Перенос диска на другую ВМ

Осоеденяем диск с данными с первой виртуальной машины

![Alt text](https://i.imgur.com/Mf57q8q.png "screen")

И подключаем ко второй виртуальной машине

![Alt text](https://i.imgur.com/20hs7LV.png "screen2")

Проверяем что диск подключился:
  ```bash
  root@fhmkl8msvme8q23be7ke:~# lsblk
  NAME   MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
  vda    254:0    0  50G  0 disk
  ├─vda1 254:1    0   1M  0 part
  └─vda2 254:2    0  50G  0 part /
  vdb    254:16   0  50G  0 disk
  └─vdb1 254:17   0  50G  0 part
  ```
- Повторяем подготовку ВМ из шагов выше и удаляем содержимое ```rm -rf /var/lib/postgresql/14/main/*```

- Останавливаем кластер: ```pg_ctlcluster 14 main stop```

- Добавляем в ```/etc/fstab```: ```/dev/vdb1 /var/lib/postgresql/ ext4 errors=remount-ro,noatime,nodiratime,user_xattr 0 0```. Выполняем ```mount -a```

- Запускаем кластер и проверяем, что данные на месте:
  ```bash
  root@fhmkl8msvme8q23be7ke:/var/lib/postgresql# pg_ctlcluster 14 main start
  root@fhmkl8msvme8q23be7ke:/var/lib/postgresql# su postgres
  postgres@fhmkl8msvme8q23be7ke:~$ psql
  psql (14.5 (Debian 14.5-2.pgdg100+2))
  Type "help" for help.

  postgres=# \l
                                    List of databases
    Name    |  Owner   | Encoding |   Collate   |    Ctype    |   Access privileges
  -----------+----------+----------+-------------+-------------+-----------------------
  postgres  | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
  template0 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
            |          |          |             |             | postgres=CTc/postgres
  template1 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
            |          |          |             |             | postgres=CTc/postgres
  (3 rows)

  postgres=# \d
          List of relations
  Schema | Name | Type  |  Owner
  --------+------+-------+----------
  public | test | table | postgres
  (1 row)

  postgres=# select * from test
  postgres-# ;
  c1
  ----
  1
  (1 row)

  postgres=#
  ```
