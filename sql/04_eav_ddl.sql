-- =====================================================================
-- CinemaDB — EAV-хранение атрибутов фильмов (домашнее задание №2)
-- Требует предварительного выполнения 01_ddl.sql (использует cinemadb.movies)
-- СУБД: MySQL 8.x (InnoDB, utf8mb4)
-- =====================================================================

USE cinemadb;

-- ---------------------------------------------------------------------
-- Типы атрибутов: определяют, какая типизированная колонка
-- attribute_values используется, и предназначение (маркетинг/служебное)
-- ---------------------------------------------------------------------
CREATE TABLE attribute_types (
    attribute_type_id  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    code                VARCHAR(30)  NOT NULL UNIQUE,
    name                VARCHAR(100) NOT NULL,
    data_type           ENUM('text', 'boolean', 'date', 'number') NOT NULL,
    is_marketing        BOOLEAN NOT NULL DEFAULT TRUE,
    description         VARCHAR(255)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Атрибуты: конкретные именованные характеристики фильма
-- (например, «Оскар», «Мировая премьера», «Рейтинг критиков (IMDb)»)
-- ---------------------------------------------------------------------
CREATE TABLE attributes (
    attribute_id       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    attribute_type_id  INT UNSIGNED NOT NULL,
    name                VARCHAR(150) NOT NULL,
    description          VARCHAR(255),
    CONSTRAINT fk_attributes_type
        FOREIGN KEY (attribute_type_id) REFERENCES attribute_types (attribute_type_id),
    CONSTRAINT uq_attribute_name UNIQUE (attribute_type_id, name)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Значения атрибутов: одна строка = одно значение одного атрибута
-- у одного фильма. Заполнена ровно одна из 4 типизированных колонок —
-- та, что соответствует data_type атрибута (см. 06_eav_queries.sql —
-- проверочный запрос на структурную целостность).
--
-- value_number — DECIMAL(12,3), а не FLOAT/DOUBLE: числа с плавающей
-- точкой в двоичном виде дают ошибки округления и неточные сравнения,
-- что критично для рейтингов и денежных показателей (кассовые сборы).
-- ---------------------------------------------------------------------
CREATE TABLE attribute_values (
    value_id       BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    movie_id       INT UNSIGNED NOT NULL,
    attribute_id   INT UNSIGNED NOT NULL,
    value_text     TEXT,
    value_boolean  BOOLEAN,
    value_date     DATE,
    value_number   DECIMAL(12,3),
    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_values_movie
        FOREIGN KEY (movie_id) REFERENCES movies (movie_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_values_attribute
        FOREIGN KEY (attribute_id) REFERENCES attributes (attribute_id),
    CONSTRAINT uq_movie_attribute UNIQUE (movie_id, attribute_id),
    INDEX idx_values_attribute (attribute_id),
    INDEX idx_values_date (value_date)
) ENGINE=InnoDB;
