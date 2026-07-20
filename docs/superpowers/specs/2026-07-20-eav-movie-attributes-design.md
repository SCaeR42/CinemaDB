# Дизайн: EAV-хранение атрибутов фильмов (CinemaDB)

Дата: 2026-07-20

## 1. Цель

Домашнее задание №2 поверх существующей нормализованной схемы CinemaDB:

- потренироваться в написании сложных SQL-запросов, проверяющих правильность структуры EAV;
- усилить схему гибким хранением значений различного типа для `movies` без нарушения нормализации основной схемы.

Требования из задания:

- 4 таблицы: фильмы, атрибуты, типы атрибутов, значения (`movies` переиспользуется из существующей схемы, новых — 3).
- Типы атрибутов из примера: рецензии (текст), премия (boolean, заменяется изображением при печати), важные даты (дата, для показа зрителю/на баннерах), служебные даты (дата, для внутреннего планирования).
- View служебных данных: фильм, задачи актуальные сегодня, задачи актуальные через 20 дней.
- View маркетинговых данных: фильм, тип атрибута, атрибут, значение (текстом).
- Критерии оценки: учтены все допустимые типы данных; учтена специфика хранения/использования float-данных; схема оснащена индексами.

## 2. Решения, принятые в ходе обсуждения

1. **Файлы** — новый самостоятельный блок (`04_eav_ddl.sql`, `05_eav_seed.sql`, `06_eav_queries.sql`, `docs/eav-model.md`), не смешивается с файлами первого ДЗ.
2. **Числовой тип атрибутов добавлен сверх примера из задания** — критерий оценки отдельно требует учесть специфику float-данных, а в примере типов такого нет. Добавлен 5-й тип `metric` (числовые показатели: рейтинг критиков, кассовые сборы и т.п.).
3. **Служебные даты исключены из маркетингового view** — они для внутреннего планирования, а не для показа зрителю/печати на баннерах/билетах.
4. **Целостность EAV обеспечивается только проверочным SQL-запросом**, не триггерами — соответствует заявленной цели ДЗ («сложные SQL-запросы для проверки правильности структуры»), а не усложнению схемы бизнес-логикой на уровне СУБД.

## 3. Схема данных

### 3.1 `attribute_types` — справочник типов атрибутов

| Поле | Тип | Ограничения |
|---|---|---|
| attribute_type_id | INT UNSIGNED | PK, AUTO_INCREMENT |
| code | VARCHAR(30) | NOT NULL, UNIQUE — машинный код (`review`, `award`, `important_date`, `service_date`, `metric`) |
| name | VARCHAR(100) | NOT NULL — отображаемое имя |
| data_type | ENUM('text','boolean','date','number') | NOT NULL — определяет, какая колонка `attribute_values` используется |
| is_marketing | BOOLEAN | NOT NULL, DEFAULT TRUE — попадает ли тип в маркетинговый view |
| description | VARCHAR(255) | NULL |

Начальные строки:

| code | name | data_type | is_marketing |
|---|---|---|---|
| review | Рецензии | text | TRUE |
| award | Премии | boolean | TRUE |
| important_date | Важные даты | date | TRUE |
| service_date | Служебные даты | date | FALSE |
| metric | Числовые показатели | number | TRUE |

### 3.2 `attributes` — конкретные атрибуты

| Поле | Тип | Ограничения |
|---|---|---|
| attribute_id | INT UNSIGNED | PK, AUTO_INCREMENT |
| attribute_type_id | INT UNSIGNED | FK → attribute_types, NOT NULL |
| name | VARCHAR(150) | NOT NULL |
| description | VARCHAR(255) | NULL |
| | | UNIQUE (attribute_type_id, name) |

Примеры (заполняются в seed): «Оскар», «Ника», «Золотой глобус» (award); «Мировая премьера», «Премьера в РФ» (important_date); «Дата начала продажи билетов», «Запуск рекламы на ТВ», «Дедлайн поставки постеров» (service_date); «Рецензия критика Волобуева», «Отзыв неизвестной киноакадемии» (review); «Рейтинг критиков (IMDb)», «Кассовые сборы, млн $» (metric).

### 3.3 `attribute_values` — значения

| Поле | Тип | Ограничения |
|---|---|---|
| value_id | BIGINT UNSIGNED | PK, AUTO_INCREMENT |
| movie_id | INT UNSIGNED | FK → movies.movie_id, NOT NULL, ON DELETE CASCADE |
| attribute_id | INT UNSIGNED | FK → attributes.attribute_id, NOT NULL |
| value_text | TEXT | NULL |
| value_boolean | BOOLEAN | NULL |
| value_date | DATE | NULL |
| value_number | DECIMAL(12,3) | NULL |
| created_at | DATETIME | NOT NULL, DEFAULT CURRENT_TIMESTAMP |
| | | UNIQUE (movie_id, attribute_id) — одно значение атрибута на фильм |
| | | INDEX (attribute_id) — обратный поиск («у каких фильмов есть Оскар») |
| | | INDEX (value_date) — для view служебных задач (диапазоны/равенство по дате) |

**Специфика float-данных**: для числовых значений используется `DECIMAL(12,3)`, а не `FLOAT`/`DOUBLE`. `FLOAT`/`DOUBLE` — двоичные типы с плавающей точкой, дающие ошибки округления при хранении и потере точности при сравнении (`value_number = 7.5` может не сработать после серии арифметических операций). `DECIMAL` — точный десятичный тип, что важно для рейтингов и денежных показателей (кассовые сборы), где округление и точное сравнение критичны.

**Один атрибут = одна типизированная колонка**: у любой строки заполнена ровно одна из 4 колонок (`value_text`/`value_boolean`/`value_date`/`value_number`), остальные — NULL. Соответствие «тип атрибута → заполненная колонка» не enforced на уровне СУБД (см. решение №4) — вместо этого пишется проверочный запрос.

## 4. Views

### `v_marketing_attributes`

Колонки: `movie_title`, `attribute_type`, `attribute_name`, `value_display`.

Источник — `attribute_values` JOIN `movies`/`attributes`/`attribute_types`, фильтр `WHERE attribute_types.is_marketing = TRUE`. `value_display` — `CASE` по `data_type`:
- text → `value_text` как есть;
- boolean → `'Да'`/`'Нет'`;
- date → `DATE_FORMAT(value_date, '%d.%m.%Y')`;
- number → `CAST(value_number AS CHAR)`.

### `v_service_tasks`

Колонки: `movie_title`, `tasks_today`, `tasks_in_20_days`.

Источник — `attribute_values` JOIN `movies`/`attributes`/`attribute_types`, фильтр `WHERE attribute_types.code = 'service_date'`, `GROUP BY movie_id`. `tasks_today` = `GROUP_CONCAT(attribute.name)` где `value_date = CURDATE()`; `tasks_in_20_days` — где `value_date = CURDATE() + INTERVAL 20 DAY`. View пересчитывается динамически при каждом обращении (не материализован).

## 5. Проверочный запрос (ядро ДЗ)

В `06_eav_queries.sql` — запрос-аудит структурной целостности EAV, находящий:
- строки, где заполнено не ровно 1 из 4 typed-колонок (0 или ≥2 одновременно);
- строки, где заполненная колонка не соответствует `attribute_types.data_type` связанного атрибута.

Плюс 1-2 демонстрационных запроса поверх views (`SELECT * FROM v_marketing_attributes WHERE movie_title = ...`, `SELECT * FROM v_service_tasks`).

## 6. Seed-данные

`05_eav_seed.sql`: 5 строк `attribute_types`, ~10 строк `attributes` (см. примеры в 3.2), значения для 3 существующих фильмов (`Начало`, `Смешные истории`, `Космический рубеж`), включая минимум одну `service_date`-запись со значением `CURDATE()` и одну со значением `CURDATE() + INTERVAL 20 DAY` — чтобы `v_service_tasks` показывал непустой результат при любом запуске seed независимо от даты.

## 7. Документация

`docs/eav-model.md` — по аналогии с `docs/logical-model.md`: назначение EAV-части, список сущностей, атрибуты/типы/ключи, связи, ER-диаграмма (mermaid), обоснование выбора DECIMAL vs FLOAT, описание views и проверочного запроса. README дополняется разделом со ссылкой на новую часть и командой развёртывания (`mysql -u root < sql/04_eav_ddl.sql` и т.д., после базовых файлов).

## 8. Вне рамок

- Не трогаем существующие таблицы/файлы первого ДЗ.
- Не добавляем триггеры или CHECK-констрейнты для типовой целостности EAV (см. решение №4).
- Не проектируем UI/приложение — только SQL.
