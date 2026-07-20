# Отчёт по производительности запросов (CinemaDB)

Все планы ниже сняты по-настоящему (`EXPLAIN ANALYZE`) на локальном
контейнере `mysql:9.6`.

## 1. Классификация запросов и отклонение от 3+3

Из 6 сформулированных бизнес-вопросов только 2 естественно сводятся к
одной таблице без потери смысла: афиша без названий фильма бессмысленна,
топ-3 прибыльных без агрегата по `tickets` не посчитать, а
свободные/занятые места без сопоставления `seats`↔`tickets` не показать.
Итог — 2 простых + 4 сложных вместо предложенных в задании 3+3.

| № | Запрос | Класс | Таблицы |
|---|---|---|---|
| 1 | Фильмы на сегодня (упрощённо, без названий) | простой | `sessions` |
| 2 | Оплаченные заказы за неделю (прокси для «билетов») | простой | `bookings` |
| 3 | Полная афиша на сегодня | сложный | `sessions`+`movies`+`halls`+`formats` |
| 4 | Топ-3 прибыльных фильма за неделю | сложный (агрегат) | `tickets`+`sessions`+`movies` |
| 5 | Схема зала: свободные/занятые места на сеанс | сложный | `seats`+`seat_types`+`tickets` |
| 6 | Теоретический диапазон цены билета на сеанс | сложный (агрегат) | `sessions`+`seats`+`seat_types` |

Полный текст запросов — [sql/07_perf_queries.sql](../sql/07_perf_queries.sql).

## 2. Объём данных

Справочники (`cinemas`/`halls`/`seat_types`/`seats`/`genres`/`formats`) не
масштабировались — остались как в `02_seed.sql` (1 кинотеатр, 2 зала, 18
мест). Масштабировались `movies`/`sessions`/`customers`/`bookings`/`tickets`:

| Таблица | Этап 1 (~10 000) | Этап 2 (~10 000 000) |
|---|---|---|
| movies | 300 | 3 000 |
| sessions | 1 200 | 700 000 |
| customers | 2 500 | 1 500 000 |
| bookings | 3 000 | 3 000 000 |
| tickets | 3 000 | 4 800 000 |
| **Итого** | **10 000** | **10 003 000** |

Числа на этапе 2 скорректированы относительно исходной спеки: 400 000
сеансов на 2 существующих зала физически не вмещали 5 097 000 билетов
(максимум ~3,6 млн уникальных пар место×сеанс при 400K сеансов). Подняли
сеансы до 700 000 (ёмкость 6,3 млн пар) и снизили билеты до 4 800 000 —
общий объём остался ~10 млн. Генератор — [sql/08_perf_seed_gen_10k.sql](../sql/08_perf_seed_gen_10k.sql)
и [sql/09_perf_seed_gen_10m.sql](../sql/09_perf_seed_gen_10m.sql), оба
построены на декартовом произведении вспомогательных таблиц чисел (без
построчных циклов и без `RECURSIVE CTE`), время генерации сеансов
центрировано на «сейчас», поэтому «сегодня»/«последняя неделя» всегда
непусты на обоих этапах (проверено: 96 сеансов «сегодня» — и на 10K, и на
10M строках).

## 3. Результаты по запросам

### Запрос 1 — фильмы на сегодня (простой)

```sql
SELECT movie_id, hall_id, start_time, end_time
FROM sessions
WHERE DATE(start_time) = CURDATE();
```

**План на 10K** (`Table scan` по всей таблице — на 1 200 строках это дёшево):
```text
-> Filter: (cast(sessions.start_time as date) = <cache>(curdate()))  (cost=122 rows=1200) (actual time=0.106..0.198 rows=96 loops=1)
    -> Table scan on sessions  (cost=122 rows=1200) (actual time=0.029..0.154 rows=1200 loops=1)
```

**План на 10M до оптимизации** (тот же полный скан, но уже 700 000 строк):
```text
-> Filter: (cast(sessions.start_time as date) = <cache>(curdate()))  (cost=71021 rows=697986) (actual time=53.8..135 rows=96 loops=1)
    -> Table scan on sessions  (cost=71021 rows=697986) (actual time=0.37..112 rows=700000 loops=1)
```

**План на 10M после добавления `idx_sessions_start_time`, тот же текст запроса** — индекс **не используется**:
```text
-> Filter: (cast(sessions.start_time as date) = <cache>(curdate()))  (cost=70384 rows=697986) (actual time=53.7..106 rows=96 loops=1)
    -> Table scan on sessions  (cost=70384 rows=697986) (actual time=0.385..82.9 rows=700000 loops=1)
```

**Причина и реальное решение:** `DATE(start_time) = CURDATE()` оборачивает
колонку в функцию — предикат становится несаргируемым, обычный B-Tree
индекс по `start_time` для него бесполезен. Переписав то же условие в
эквивалентном диапазонном виде (без оборачивания колонки), индекс
подключается и запрос ускоряется в ~1100 раз:

```sql
SELECT movie_id, hall_id, start_time, end_time
FROM sessions
WHERE start_time >= CURDATE() AND start_time < CURDATE() + INTERVAL 1 DAY;
```
```text
-> Index range scan on sessions using idx_sessions_start_time over ('2026-07-20 00:00:00' <= start_time < '2026-07-21 00:00:00'), with index condition: (...)  (cost=43.5 rows=96) (actual time=0.0894..0.0952 rows=96 loops=1)
```

**Что улучшилось:** 106 мс → 0,095 мс (индекс сам по себе бесполезен для
исходной формулировки запроса — нужна ещё и переформулировка предиката).

### Запрос 2 — оплаченные заказы за неделю (простой)

```sql
SELECT COUNT(*) FROM bookings
WHERE status = 'paid' AND booking_date >= CURDATE() - INTERVAL 7 DAY;
```

**План на 10K:**
```text
-> Aggregate: count(0)  (cost=312 rows=1) (actual time=0.406..0.406 rows=1 loops=1)
    -> Filter: ((bookings.status = 'paid') and (bookings.booking_date >= <cache>((curdate() - interval 7 day))))  (cost=235 rows=333) (actual time=0.0396..0.403 rows=8 loops=1)
        -> Table scan on bookings  (cost=235 rows=3000) (actual time=0.0327..0.275 rows=3000 loops=1)
```

**План на 10M до оптимизации:**
```text
-> Aggregate: count(0)  (cost=315268 rows=1) (actual time=463..463 rows=1 loops=1)
    -> Filter: ((bookings.status = 'paid') and (bookings.booking_date >= <cache>((curdate() - interval 7 day))))  (cost=238622 rows=332641) (actual time=4.18..462 rows=5340 loops=1)
        -> Table scan on bookings  (cost=238622 rows=2.99e+6) (actual time=4.17..337 rows=3e+6 loops=1)
```

**План на 10M после добавления `idx_bookings_status_date`:**
```text
-> Aggregate: count(0)  (cost=2306 rows=1) (actual time=1.01..1.01 rows=1 loops=1)
    -> Filter: (...)  (cost=1076 rows=5340) (actual time=0.0454..0.87 rows=5340 loops=1)
        -> Covering index range scan on bookings using idx_bookings_status_date over (status = 'paid' AND '2026-07-13 00:00:00' <= booking_date)  (cost=1076 rows=5340) (actual time=0.0419..0.512 rows=5340 loops=1)
```

**Что улучшилось:** полный скан 3 000 000 строк → покрывающий диапазонный
скан индекса, 463 мс → 1,01 мс (~460 раз быстрее). Единственный из 6
запросов, где ровно предложенный индекс сработал «в лоб», без
дополнительной переформулировки.

### Запрос 3 — полная афиша на сегодня (сложный)

**План на 10K** (оптимизатор уже неплохо справлялся на маленькой таблице,
используя `uq_hall_start_time`):
```text
-> Sort: h.name, s.start_time  (actual time=0.526..0.532 rows=96 loops=1)
    -> ... Index lookup on s using uq_hall_start_time (hall_id = h.hall_id), with index condition: (cast(s.start_time as date) = <cache>(curdate()))  (cost=12 rows=600) (actual time=0.0737..0.0768 rows=48 loops=4)
```

**План на 10M до оптимизации** (та же проблема, что в запросе 1 — полный
скан `sessions` внутри JOIN):
```text
-> Sort: h.name, s.start_time  (actual time=240..240 rows=96 loops=1)
    -> Stream results  (cost=1.17e+6 rows=2.79e+6) (actual time=106..240 rows=96 loops=1)
        -> Nested loop inner join (...)
            -> Filter: (cast(s.start_time as date) = <cache>(curdate()))  (cost=280425 rows=2.79e+6) (actual time=106..239 rows=96 loops=1)
                -> Inner hash join (s.hall_id = h.hall_id), (s.format_id = f.format_id)  (cost=280425 rows=2.79e+6) (actual time=4.14..216 rows=700000 loops=1)
                    -> Table scan on s  (cost=17757 rows=697986) (actual time=0.431..149 rows=700000 loops=1)
```

**План на 10M после `idx_sessions_start_time`, тот же текст запроса** —
снова не используется (тот же `DATE()`-wrap, что в запросе 1):
```text
-> Table scan on s  (cost=17597 rows=697986) (actual time=0.45..115 rows=700000 loops=1)
```

**После переформулировки предиката в диапазонный вид** (как в запросе 1):
```text
-> Sort: h.name, s.start_time  (actual time=1.18..1.18 rows=96 loops=1)
    -> ...
        -> Index range scan on s using idx_sessions_start_time over ('2026-07-20 00:00:00' <= start_time < '2026-07-21 00:00:00'), with index condition: (...)  (cost=0.339 rows=96) (actual time=0.0887..0.0964 rows=96 loops=1)
```

**Что улучшилось:** 240 мс → 1,18 мс (~200 раз быстрее), но опять только
вместе с переформулировкой запроса, не одним индексом.

### Запрос 4 — топ-3 прибыльных фильма за неделю (сложный, агрегат)

**План на 10K:** полная реализация за 5,16 мс.

**План на 10M до оптимизации** — оптимизатор выбрал обходной путь через
`movies` (3 000 итераций) вместо скана `sessions`:
```text
-> Limit: 3 row(s)  (actual time=6298..6298 rows=3 loops=1)
    -> ...
        -> Nested loop inner join (...)
            -> Nested loop inner join (...)
                -> Table scan on m  (cost=368 rows=2867) (actual time=2.15..13.8 rows=3000 loops=1)
                -> Filter: (s.start_time >= <cache>((curdate() - interval 7 day)))  (...)
                    -> Index lookup on s using fk_sessions_movie (movie_id = m.movie_id)  (...)
```
Самый медленный запрос из всех: **6,3 секунды**.

**План на 10M после добавления индексов** (оптимизатор сам сменил стратегию
на скан `tickets` целиком + PK-джойн `sessions`, индекс `idx_sessions_start_time`
использован не был):
```text
-> Limit: 3 row(s)  (actual time=5007..5007 rows=3 loops=1)
    -> ...
        -> Table scan on t  (cost=488967 rows=4.79e+6) (actual time=2.53..819 rows=4.8e+6 loops=1)
```
5 007 мс — на 20% быстрее, но не из-за нового индекса, а из-за
обновлённой статистики (`ANALYZE TABLE`), которая изменила выбор плана.

**С принудительным использованием `idx_sessions_start_time` (`FORCE INDEX`)**:
```text
-> Index range scan on s using idx_sessions_start_time over ('2026-07-13 00:00:00' <= start_time), with index condition: (...)  (cost=157047 rows=348993) (actual time=4.14..280 rows=350748 loops=1)
```
Итоговое время всего запроса с `FORCE INDEX`: **4 200 мс**.

**Что улучшилось (честно):** индекс *может* дать ~33% ускорение (6 298 →
4 200 мс), но оптимизатор MySQL по умолчанию его не выбирает для этого
конкретного запроса (предпочитает полный скан `tickets`) — классический
случай, когда cost-based оптимизатор ошибается с оценкой избирательности
джойна, и одного добавленного индекса недостаточно; для гарантированного
эффекта нужен `FORCE INDEX` или дальнейшая настройка статистики/структуры
запроса, что выходит за рамки этого ДЗ, но зафиксировано как честная находка.

### Запрос 5 — свободные/занятые места на сеанс (сложный)

**План на 10K:** 0,038 мс. **План на 10M до оптимизации:** 1,8 мс. **План
на 10M после:** 0,898 мс. Запрос уже был хорошо индексирован через
`uq_seat_position`/`uq_session_seat` с самого начала (ни один из двух новых
индексов его не затрагивает) — разница до/после в пределах естественного
разброса (прогретый кэш), не связана с оптимизацией.

### Запрос 6 — теоретический диапазон цены билета (сложный, агрегат)

**План на 10K:** 0,032 мс. **План на 10M до оптимизации:** 1,46 мс. **План
на 10M после:** 0,032 мс. План выполнения идентичен во всех трёх случаях
(`Filter: (se.hall_id = '1')`, `Index lookup ... using fk_seats_type`) —
ни один из двух добавленных индексов к этому запросу не относится
(`sessions`/`seats`/`seat_types`, фильтр по `session_id`, не по датам).
Разница в 1,46 мс, вероятно, — эффект холодного/прогретого кэша буферного
пула при первом обращении к странице после массовой генерации данных, а не
результат оптимизации.

## 4. Предложенные оптимизации

1. **`CREATE INDEX idx_sessions_start_time ON sessions (start_time);`**
   Устраняет полный скан `sessions` для запросов 1/3 (и частично 4) —
   **но только если запрос переписан в саргируемом виде** (`start_time >=
   X AND start_time < Y` вместо `DATE(start_time) = X`). Индекс на голую
   колонку не помогает, пока предикат оборачивает её в функцию — это
   главный практический вывод отчёта: индексы работают в паре с формой
   запроса, а не отдельно от неё. Рекомендация: в реальном приложении
   держать `sessions.start_time` без функциональной обёртки в WHERE (или
   завести функциональный индекс `((DATE(start_time)))`, если запрос с
   `DATE()` менять нельзя).

2. **`CREATE INDEX idx_bookings_status_date ON bookings (status, booking_date);`**
   Чистый выигрыш «в лоб» для запроса 2: полный скан 3 млн строк →
   покрывающий диапазонный скан индекса, 463 мс → 1,01 мс (~460×).
   Равенство (`status`) — ведущей колонкой индекса, диапазон
   (`booking_date`) — второй, по стандартному правилу построения составных
   индексов "равенство + диапазон".

3. **Запрос 4 требует отдельного внимания** — ни один из двух индексов не
   даёт оптимизатору однозначно лучший план автоматически; `FORCE INDEX
   (idx_sessions_start_time)` даёт ~33% ускорение (6 298 → 4 200 мс), но
   MySQL сам его не выбирает. Для настоящего продакшена здесь стоило бы
   либо использовать хинт/`FORCE INDEX`, либо пересмотреть структуру
   запроса (например, материализовать выручку по неделям в отдельную
   агрегирующую таблицу, если такой отчёт запрашивается часто).

4. **Индексы 5 и 6 не тронуты** — они уже были оптимальны на существующих
   уникальных индексах (`uq_seat_position`, `uq_session_seat`) с самого
   начала; добавлять что-то дополнительно не потребовалось.

## 5. Топ-15 объектов БД по размеру (после оптимизации, 10M строк)

| Таблица | Индекс | Размер, МБ |
|---|---|---|
| tickets | PRIMARY | 200.70 |
| customers | PRIMARY | 198.70 |
| tickets | fk_tickets_booking | 125.70 |
| customers | email | 114.92 |
| tickets | uq_session_seat | 108.69 |
| bookings | PRIMARY | 100.61 |
| bookings | fk_bookings_customer | 89.64 |
| tickets | fk_tickets_seat | 63.61 |
| bookings | idx_bookings_status_date | 51.58 |
| sessions | PRIMARY | 36.56 |
| customers | phone | 34.59 |
| sessions | uq_hall_start_time | 13.55 |
| sessions | fk_sessions_movie | 12.52 |
| sessions | idx_sessions_start_time | 11.52 |
| sessions | fk_sessions_format | 10.52 |

`tickets` и `customers` доминируют, как и ожидалось для таблиц с наибольшим
числом строк (4,8 млн и 1,5 млн соответственно) и/или самыми широкими
строками. Оба новых индекса (`idx_bookings_status_date` — 51,58 МБ,
`idx_sessions_start_time` — 11,52 МБ) заметны, но далеко не самые тяжёлые
объекты в базе — цена за их выигрыш в скорости невысока относительно
общего объёма.

## 6. Топ-5 самых используемых индексов (после прогона нагрузки)

| Таблица | Индекс | Обращений |
|---|---|---|
| sessions | PRIMARY | 14 749 937 |
| movies | PRIMARY | 8 119 634 |
| seats | uq_seat_position | 6 310 904 |
| seats | PRIMARY | 4 803 006 |
| tickets | fk_tickets_booking | 4 803 000 |

Лидирует `sessions.PRIMARY` — не удивительно, учитывая, что все 6 запросов
так или иначе проходят через `sessions` (напрямую или через JOIN), а
генерация `tickets` в самом набросе данных тоже интенсивно обращалась к
`sessions`/`seats` через PK.

## 7. Топ-5 наименее используемых индексов

| Таблица | Индекс | Обращений |
|---|---|---|
| attribute_values | idx_values_date | 0 |
| sessions | uq_hall_start_time | 0 |
| movie_genres | fk_mg_genre | 0 |
| seat_types | name | 0 |
| — | (ties, 0 обращений) | 0 |

`attribute_values`/`movie_genres` пустые в этом контейнере (EAV и жанры не
участвуют в нагрузке) — их 0 обращений ожидаемо и не говорит о
бесполезности индекса самого по себе. Единственный содержательный
кандидат — **`sessions.uq_hall_start_time`**: ни один из 6 запросов не
фильтрует одновременно по `hall_id` и `start_time`, поэтому индекс не
использовался ни разу за весь прогон. Тем не менее удалять его нельзя —
это не просто ускоряющий индекс, а `UNIQUE`-ограничение, обеспечивающее
бизнес-правило «в одном зале не может быть двух сеансов с одинаковым
временем начала»; 0 обращений в SELECT-нагрузке не отменяет его роли при
INSERT. Это иллюстрирует общее правило: решение об удалении индекса по
статистике использования должно учитывать, не является ли он также
constraint'ом.
