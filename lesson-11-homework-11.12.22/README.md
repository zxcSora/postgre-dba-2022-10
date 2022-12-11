
## Подготавливаем окружение
- Создал машинку в YC via TF. Через user-data прокинул публичный ключ.
```bash
sudo apt-get update
sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release -y
```


- Устанавливаем PostgreSQL 14
```bash
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get install \
  postgresql-14 -y
```
```SQL
postgres=# select version();
                                                     version
------------------------------------------------------------------------------------------------------------------
 PostgreSQL 14.6 (Debian 14.6-1.pgdg100+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 8.3.0-6) 8.3.0, 64-bit
(1 row)
```

- Настройка PostgreSQL (Максимальная производительность)

Сначала посмотрим, какие показатели получаться "из коробки":
```bash
postgres@fhmgol9ht51m3a8vj77j:/root$ pgbench -c 50 -j 2 -P 5 -T 30 postgres
pgbench (14.6 (Debian 14.6-1.pgdg100+1))
starting vacuum...end.
progress: 5.0 s, 458.6 tps, lat 103.772 ms stddev 87.119
progress: 10.0 s, 366.4 tps, lat 137.315 ms stddev 156.785
progress: 15.0 s, 420.0 tps, lat 118.619 ms stddev 104.397
progress: 20.0 s, 430.2 tps, lat 116.067 ms stddev 95.633
progress: 25.0 s, 436.0 tps, lat 114.675 ms stddev 115.595
progress: 30.0 s, 431.8 tps, lat 117.165 ms stddev 131.349
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 50
number of threads: 2
duration: 30 s
number of transactions actually processed: 12765
latency average = 117.401 ms
latency stddev = 116.389 ms
initial connection time = 93.557 ms
tps = 424.609876 (without initial connection time)

```

Далее пробуем затюнить на максимальную производительность

- Изменяем значение `shared_buffers` на 33% от RAM. У меня 2GB Памяти поэтому 676MB.
- `max_connections` - Ставим 100, т.к. в нашей ситуации мы должны масксимально убрать все ограничения.
- `effective_cache_size` - Устанавливаем максимальный объем ОП -  2GB
- `random_page_cost` - Ставим 1.1 т.к. объем данных в моём случае 100MB
- `work_mem` - попробуем поставить 128MB для начала
- `wal_buffers` - 16MB, ставим максимальное рекомендованое значение.
- `max_wal_size` - Ставлю 16GB, чтобы валы максимально долго не сбрасывались на диск
- `checkpoint_timeout` - Ставлю 1 час, минимизируя ущерб производительности от этой операции
- `effective_io_concurrency` - 200 т.к. я использую ssd

```bash
postgres@fhmgol9ht51m3a8vj77j:/root$ pgbench -c 50 -j 2 -P 5 -T 30 postgres
pgbench (14.6 (Debian 14.6-1.pgdg100+1))
starting vacuum...end.
progress: 5.0 s, 361.2 tps, lat 129.353 ms stddev 130.279
progress: 10.0 s, 458.0 tps, lat 111.434 ms stddev 123.098
progress: 15.0 s, 484.2 tps, lat 103.774 ms stddev 92.864
progress: 20.0 s, 487.4 tps, lat 102.374 ms stddev 91.312
progress: 25.0 s, 459.4 tps, lat 108.789 ms stddev 107.646
progress: 30.0 s, 490.4 tps, lat 102.188 ms stddev 103.025
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 50
number of threads: 2
duration: 30 s
number of transactions actually processed: 13753
latency average = 108.930 ms
latency stddev = 108.255 ms
initial connection time = 105.075 ms
tps = 457.587742 (without initial connection time)

```
Видим, что получили прирост на ~30 TPS

Попробуем воспользоваться pgtune
```bash
max_connections = 60
shared_buffers = 512MB
effective_cache_size = 1536MB
maintenance_work_mem = 128MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 4369kB
min_wal_size = 2GB
max_wal_size = 8GB
```
Результат:
```
postgres@fhmgol9ht51m3a8vj77j:/root$ pgbench -c 50 -j 2 -P 5 -T 30 postgres
pgbench (14.6 (Debian 14.6-1.pgdg100+1))
starting vacuum...end.
progress: 5.0 s, 444.8 tps, lat 107.850 ms stddev 89.604
progress: 10.0 s, 455.8 tps, lat 109.775 ms stddev 100.356
progress: 15.0 s, 483.2 tps, lat 103.309 ms stddev 90.244
progress: 20.0 s, 480.2 tps, lat 103.814 ms stddev 96.961
progress: 25.0 s, 465.8 tps, lat 107.495 ms stddev 91.900
progress: 30.0 s, 322.4 tps, lat 152.407 ms stddev 146.242
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 50
number of threads: 2
duration: 30 s
number of transactions actually processed: 13311
latency average = 112.839 ms
latency stddev = 104.283 ms
initial connection time = 96.663 ms
tps = 441.178942 (without initial connection time)
```
