-- =====================================================================
-- CinemaDB — EAV: демонстрационные данные (домашнее задание №2)
-- Требует предварительного выполнения 01_ddl.sql, 02_seed.sql, 04_eav_ddl.sql
-- =====================================================================

USE cinemadb;

INSERT INTO attribute_types (code, name, data_type, is_marketing, description) VALUES
    ('review',         'Рецензии',            'text',    TRUE,  'Текстовые рецензии критиков и киноакадемий'),
    ('award',          'Премии',              'boolean', TRUE,  'Получена ли премия; при печати заменяется изображением'),
    ('important_date', 'Важные даты',         'date',    TRUE,  'Даты, важные для зрителя (премьеры и т.п.)'),
    ('service_date',   'Служебные даты',      'date',    FALSE, 'Даты для внутреннего планирования, не для печати'),
    ('metric',         'Числовые показатели', 'number',  TRUE,  'Точные числовые показатели: официальный рейтинг, кассовые сборы — округление недопустимо'),
    ('rating',         'Средние оценки',      'float',   TRUE,  'Агрегированные/вычисляемые приближённые величины (среднее по множеству пользовательских оценок) — точность IEEE754 ожидаема и достаточна');

-- attribute_type_id: 1=review, 2=award, 3=important_date, 4=service_date, 5=metric, 6=rating
INSERT INTO attributes (attribute_type_id, name) VALUES
    (1, 'Рецензия критика Романа Волобуева'),          -- attribute_id 1
    (1, 'Отзыв неизвестной киноакадемии'),             -- attribute_id 2
    (2, 'Оскар'),                                      -- attribute_id 3
    (2, 'Ника'),                                       -- attribute_id 4
    (2, 'Золотой глобус'),                             -- attribute_id 5
    (3, 'Мировая премьера'),                           -- attribute_id 6
    (3, 'Премьера в РФ'),                              -- attribute_id 7
    (4, 'Дата начала продажи билетов'),                -- attribute_id 8
    (4, 'Запуск рекламы на ТВ'),                       -- attribute_id 9
    (4, 'Дедлайн поставки постеров в залы'),           -- attribute_id 10
    (5, 'Рейтинг критиков (IMDb)'),                    -- attribute_id 11
    (5, 'Кассовые сборы, млн $'),                      -- attribute_id 12
    (6, 'Средняя пользовательская оценка');            -- attribute_id 13

-- Фильм 1: «Начало» (movie_id = 1)
INSERT INTO attribute_values (movie_id, attribute_id, value_text) VALUES
    (1, 1, 'Гипнотическое кино про архитектуру снов — Нолан на пике формы.');
INSERT INTO attribute_values (movie_id, attribute_id, value_boolean) VALUES
    (1, 3, TRUE),   -- Оскар
    (1, 4, FALSE);  -- Ника
INSERT INTO attribute_values (movie_id, attribute_id, value_date) VALUES
    (1, 6, '2023-04-20'),                    -- Мировая премьера
    (1, 7, '2023-05-01'),                    -- Премьера в РФ
    (1, 8, CURDATE()),                       -- Дата начала продажи билетов (сегодня)
    (1, 9, CURDATE() + INTERVAL 20 DAY);     -- Запуск рекламы на ТВ (через 20 дней)
INSERT INTO attribute_values (movie_id, attribute_id, value_number) VALUES
    (1, 11, 8.800),
    (1, 12, 836.848);
-- 7.1 намеренно взято как классический пример: не имеет точного двоичного
-- представления в IEEE 754 (см. демонстрацию специфики float в 06_eav_queries.sql)
INSERT INTO attribute_values (movie_id, attribute_id, value_float) VALUES
    (1, 13, 7.1);

-- Фильм 2: «Смешные истории» (movie_id = 2)
INSERT INTO attribute_values (movie_id, attribute_id, value_text) VALUES
    (2, 2, 'Лёгкая комедия для семейного просмотра.');
INSERT INTO attribute_values (movie_id, attribute_id, value_boolean) VALUES
    (2, 3, FALSE);  -- Оскар
INSERT INTO attribute_values (movie_id, attribute_id, value_date) VALUES
    (2, 6, '2024-01-05'),                    -- Мировая премьера
    (2, 8, CURDATE() + INTERVAL 20 DAY),     -- Дата начала продажи билетов (через 20 дней)
    (2, 10, CURDATE());                      -- Дедлайн поставки постеров (сегодня)
INSERT INTO attribute_values (movie_id, attribute_id, value_number) VALUES
    (2, 11, 6.500);
INSERT INTO attribute_values (movie_id, attribute_id, value_float) VALUES
    (2, 13, 6.3);

-- Фильм 3: «Космический рубеж» (movie_id = 3)
INSERT INTO attribute_values (movie_id, attribute_id, value_text) VALUES
    (3, 1, 'Достойный последователь традиций твёрдой научной фантастики.');
INSERT INTO attribute_values (movie_id, attribute_id, value_boolean) VALUES
    (3, 4, TRUE);   -- Ника
INSERT INTO attribute_values (movie_id, attribute_id, value_date) VALUES
    (3, 7, '2024-03-15'),   -- Премьера в РФ
    (3, 9, CURDATE());      -- Запуск рекламы на ТВ (сегодня)
INSERT INTO attribute_values (movie_id, attribute_id, value_number) VALUES
    (3, 12, 412.300);
INSERT INTO attribute_values (movie_id, attribute_id, value_float) VALUES
    (3, 13, 7.8);
