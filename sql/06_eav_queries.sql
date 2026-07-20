-- =====================================================================
-- CinemaDB — EAV: views и проверочные запросы (домашнее задание №2)
-- Требует предварительного выполнения 04_eav_ddl.sql (и 05_eav_seed.sql
-- для демонстрационных данных)
-- =====================================================================

USE cinemadb;

-- ---------------------------------------------------------------------
-- View «маркетинговые данные»: фильм, тип атрибута, атрибут, значение
-- (значение всегда приводится к тексту — для печати на баннерах/билетах).
-- Служебные даты (is_marketing = FALSE) в этот view не попадают.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_marketing_attributes AS
SELECT
    m.movie_id,
    m.title AS movie_title,
    at.name AS attribute_type,
    a.name  AS attribute_name,
    CASE at.data_type
        WHEN 'text'    THEN v.value_text
        WHEN 'boolean' THEN IF(v.value_boolean, 'Да', 'Нет')
        WHEN 'date'    THEN DATE_FORMAT(v.value_date, '%d.%m.%Y')
        WHEN 'number'  THEN CAST(v.value_number AS CHAR)
    END AS value_display
FROM attribute_values v
JOIN movies m           ON m.movie_id = v.movie_id
JOIN attributes a       ON a.attribute_id = v.attribute_id
JOIN attribute_types at ON at.attribute_type_id = a.attribute_type_id
WHERE at.is_marketing = TRUE;

-- ---------------------------------------------------------------------
-- View «служебные задачи»: фильм, задачи актуальные сегодня,
-- задачи актуальные через 20 дней (только тип service_date).
-- Пересчитывается динамически при каждом обращении (CURDATE()).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_service_tasks AS
SELECT
    m.movie_id,
    m.title AS movie_title,
    GROUP_CONCAT(
        CASE WHEN v.value_date = CURDATE() THEN a.name END
        ORDER BY a.name SEPARATOR '; '
    ) AS tasks_today,
    GROUP_CONCAT(
        CASE WHEN v.value_date = CURDATE() + INTERVAL 20 DAY THEN a.name END
        ORDER BY a.name SEPARATOR '; '
    ) AS tasks_in_20_days
FROM attribute_values v
JOIN movies m           ON m.movie_id = v.movie_id
JOIN attributes a       ON a.attribute_id = v.attribute_id
JOIN attribute_types at ON at.attribute_type_id = a.attribute_type_id
WHERE at.code = 'service_date'
GROUP BY m.movie_id, m.title;

-- ---------------------------------------------------------------------
-- Проверочный запрос: структурная целостность EAV.
-- Находит строки attribute_values, где:
--   1) заполнено не ровно 1 из 4 типизированных значений (0 или >=2), или
--   2) заполненная колонка не соответствует data_type атрибута.
-- В корректно заполненной схеме запрос должен возвращать 0 строк.
-- ---------------------------------------------------------------------
SELECT
    v.value_id,
    m.title        AS movie_title,
    a.name         AS attribute_name,
    at.name        AS attribute_type,
    at.data_type,
    v.value_text,
    v.value_boolean,
    v.value_date,
    v.value_number
FROM attribute_values v
JOIN movies m           ON m.movie_id = v.movie_id
JOIN attributes a       ON a.attribute_id = v.attribute_id
JOIN attribute_types at ON at.attribute_type_id = a.attribute_type_id
WHERE
    (
        (v.value_text    IS NOT NULL) +
        (v.value_boolean IS NOT NULL) +
        (v.value_date    IS NOT NULL) +
        (v.value_number  IS NOT NULL)
    ) <> 1
    OR (at.data_type = 'text'    AND v.value_text    IS NULL)
    OR (at.data_type = 'boolean' AND v.value_boolean IS NULL)
    OR (at.data_type = 'date'    AND v.value_date    IS NULL)
    OR (at.data_type = 'number'  AND v.value_number  IS NULL);

-- ---------------------------------------------------------------------
-- Демонстрация: маркетинговая выгрузка по всем фильмам
-- ---------------------------------------------------------------------
SELECT * FROM v_marketing_attributes ORDER BY movie_title, attribute_type, attribute_name;

-- ---------------------------------------------------------------------
-- Демонстрация: служебные задачи на сегодня / через 20 дней
-- ---------------------------------------------------------------------
SELECT * FROM v_service_tasks ORDER BY movie_title;
