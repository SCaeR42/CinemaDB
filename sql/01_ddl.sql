-- =====================================================================
-- CinemaDB — DDL-скрипт схемы базы данных системы управления кинотеатром
-- СУБД: MySQL 8.x (InnoDB, utf8mb4)
-- =====================================================================

CREATE DATABASE IF NOT EXISTS cinemadb
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE cinemadb;

-- ---------------------------------------------------------------------
-- Кинотеатры (сеть может состоять из нескольких кинотеатров)
-- ---------------------------------------------------------------------
CREATE TABLE cinemas (
    cinema_id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name          VARCHAR(150) NOT NULL,
    address       VARCHAR(255) NOT NULL,
    phone         VARCHAR(20)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Залы кинотеатра
-- ---------------------------------------------------------------------
CREATE TABLE halls (
    hall_id       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    cinema_id     INT UNSIGNED NOT NULL,
    name          VARCHAR(50) NOT NULL,
    description   VARCHAR(255),
    CONSTRAINT fk_halls_cinema
        FOREIGN KEY (cinema_id) REFERENCES cinemas (cinema_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_hall_name UNIQUE (cinema_id, name)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Типы мест: определяют наценку к базовой цене сеанса
-- (Стандарт / Комфорт / VIP и т.п. — места в зале стоят по-разному)
-- ---------------------------------------------------------------------
CREATE TABLE seat_types (
    seat_type_id      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name               VARCHAR(50) NOT NULL UNIQUE,
    price_multiplier   DECIMAL(4,2) NOT NULL DEFAULT 1.00
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Места в зале (описывают физическую схему зала: ряд/место/тип)
-- ---------------------------------------------------------------------
CREATE TABLE seats (
    seat_id       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hall_id       INT UNSIGNED NOT NULL,
    row_num       SMALLINT UNSIGNED NOT NULL,
    seat_number   SMALLINT UNSIGNED NOT NULL,
    seat_type_id  INT UNSIGNED NOT NULL,
    CONSTRAINT fk_seats_hall
        FOREIGN KEY (hall_id) REFERENCES halls (hall_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_seats_type
        FOREIGN KEY (seat_type_id) REFERENCES seat_types (seat_type_id),
    CONSTRAINT uq_seat_position UNIQUE (hall_id, row_num, seat_number)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Жанры
-- ---------------------------------------------------------------------
CREATE TABLE genres (
    genre_id   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(50) NOT NULL UNIQUE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Фильмы
-- ---------------------------------------------------------------------
CREATE TABLE movies (
    movie_id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    title               VARCHAR(255) NOT NULL,
    original_title      VARCHAR(255),
    description          TEXT,
    duration_minutes     SMALLINT UNSIGNED NOT NULL,
    release_date         DATE,
    age_rating           VARCHAR(10),
    country              VARCHAR(100),
    director             VARCHAR(150)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Связь фильм <-> жанр (многие-ко-многим)
-- ---------------------------------------------------------------------
CREATE TABLE movie_genres (
    movie_id   INT UNSIGNED NOT NULL,
    genre_id   INT UNSIGNED NOT NULL,
    PRIMARY KEY (movie_id, genre_id),
    CONSTRAINT fk_mg_movie
        FOREIGN KEY (movie_id) REFERENCES movies (movie_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_mg_genre
        FOREIGN KEY (genre_id) REFERENCES genres (genre_id)
        ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Форматы показа (2D / 3D / IMAX / 4DX ...)
-- ---------------------------------------------------------------------
CREATE TABLE formats (
    format_id  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(20) NOT NULL UNIQUE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Сеансы: конкретный показ фильма в конкретном зале в конкретное время.
-- Цена сеанса не одинакова для всех — зависит от формата и времени показа,
-- итоговая цена билета дополнительно зависит от типа места (см. tickets.price)
-- ---------------------------------------------------------------------
CREATE TABLE sessions (
    session_id   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    movie_id     INT UNSIGNED NOT NULL,
    hall_id      INT UNSIGNED NOT NULL,
    format_id    INT UNSIGNED NOT NULL,
    start_time   DATETIME NOT NULL,
    end_time     DATETIME NOT NULL,
    base_price   DECIMAL(10,2) NOT NULL,
    CONSTRAINT fk_sessions_movie
        FOREIGN KEY (movie_id) REFERENCES movies (movie_id),
    CONSTRAINT fk_sessions_hall
        FOREIGN KEY (hall_id) REFERENCES halls (hall_id),
    CONSTRAINT fk_sessions_format
        FOREIGN KEY (format_id) REFERENCES formats (format_id),
    CONSTRAINT chk_session_time CHECK (end_time > start_time),
    -- один и тот же зал не может использоваться под два сеанса,
    -- начинающихся в одну и ту же минуту
    CONSTRAINT uq_hall_start_time UNIQUE (hall_id, start_time)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Клиенты
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    first_name          VARCHAR(100) NOT NULL,
    last_name            VARCHAR(100) NOT NULL,
    email                VARCHAR(150) UNIQUE,
    phone                VARCHAR(20) UNIQUE,
    registration_date    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Заказы: один заказ клиента может включать несколько билетов
-- (например, вся компания покупает билеты одним заказом)
-- ---------------------------------------------------------------------
CREATE TABLE bookings (
    booking_id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    customer_id    INT UNSIGNED NOT NULL,
    booking_date   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status         ENUM('pending', 'paid', 'cancelled') NOT NULL DEFAULT 'pending',
    CONSTRAINT fk_bookings_customer
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Билеты: конкретное место на конкретном сеансе в рамках заказа.
-- price фиксируется на момент покупки (не пересчитывается задним числом,
-- даже если после изменится базовая цена сеанса или наценка типа места)
-- ---------------------------------------------------------------------
CREATE TABLE tickets (
    ticket_id    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    booking_id   INT UNSIGNED NOT NULL,
    session_id   INT UNSIGNED NOT NULL,
    seat_id      INT UNSIGNED NOT NULL,
    price        DECIMAL(10,2) NOT NULL,
    status       ENUM('booked', 'paid', 'cancelled', 'used') NOT NULL DEFAULT 'booked',
    CONSTRAINT fk_tickets_booking
        FOREIGN KEY (booking_id) REFERENCES bookings (booking_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_tickets_session
        FOREIGN KEY (session_id) REFERENCES sessions (session_id),
    CONSTRAINT fk_tickets_seat
        FOREIGN KEY (seat_id) REFERENCES seats (seat_id),
    -- одно и то же место на одном и том же сеансе нельзя продать дважды
    CONSTRAINT uq_session_seat UNIQUE (session_id, seat_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Платежи по заказу
-- ---------------------------------------------------------------------
CREATE TABLE payments (
    payment_id      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    booking_id      INT UNSIGNED NOT NULL,
    amount           DECIMAL(10,2) NOT NULL,
    payment_method   ENUM('cash', 'card', 'online') NOT NULL,
    payment_date     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status           ENUM('success', 'failed', 'refunded') NOT NULL,
    CONSTRAINT fk_payments_booking
        FOREIGN KEY (booking_id) REFERENCES bookings (booking_id)
) ENGINE=InnoDB;
