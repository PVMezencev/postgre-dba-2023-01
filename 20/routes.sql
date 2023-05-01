--
-- PostgreSQL database dump
--

-- Dumped from database version 15.2 (Debian 15.2-1.pgdg110+1)
-- Dumped by pg_dump version 15.2 (Debian 15.2-1.pgdg110+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: routes; Type: VIEW; Schema: bookings; Owner: postgres
--

CREATE VIEW bookings.routes AS
WITH f3 AS (
    SELECT f2.flight_no,
           f2.departure_airport,
           f2.arrival_airport,
           f2.aircraft_code,
           f2.duration,
           array_agg(f2.days_of_week) AS days_of_week
    FROM ( SELECT f1.flight_no,
                  f1.departure_airport,
                  f1.arrival_airport,
                  f1.aircraft_code,
                  f1.duration,
                  f1.days_of_week
           FROM ( SELECT flights.flight_no,
                         flights.departure_airport,
                         flights.arrival_airport,
                         flights.aircraft_code,
                         (flights.scheduled_arrival - flights.scheduled_departure) AS duration,
                         (to_char(flights.scheduled_departure, 'ID'::text))::integer AS days_of_week
                  FROM bookings.flights) f1
           GROUP BY f1.flight_no, f1.departure_airport, f1.arrival_airport, f1.aircraft_code, f1.duration, f1.days_of_week
           ORDER BY f1.flight_no, f1.departure_airport, f1.arrival_airport, f1.aircraft_code, f1.duration, f1.days_of_week) f2
    GROUP BY f2.flight_no, f2.departure_airport, f2.arrival_airport, f2.aircraft_code, f2.duration
)
SELECT f3.flight_no,
       f3.departure_airport,
       dep.airport_name AS departure_airport_name,
       dep.city AS departure_city,
       f3.arrival_airport,
       arr.airport_name AS arrival_airport_name,
       arr.city AS arrival_city,
       f3.aircraft_code,
       f3.duration,
       f3.days_of_week
FROM f3,
     bookings.airports dep,
     bookings.airports arr
WHERE ((f3.departure_airport = dep.airport_code) AND (f3.arrival_airport = arr.airport_code));


ALTER TABLE bookings.routes OWNER TO postgres;

--
-- Name: VIEW routes; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON VIEW bookings.routes IS 'Routes';


--
-- Name: COLUMN routes.flight_no; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.routes.flight_no IS 'Flight number';


--
-- Name: COLUMN routes.departure_airport; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.routes.departure_airport IS 'Code of airport of departure';


--
-- Name: COLUMN routes.departure_airport_name; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.routes.departure_airport_name IS 'Name of airport of departure';


--
-- Name: COLUMN routes.departure_city; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.routes.departure_city IS 'City of departure';


--
-- Name: COLUMN routes.arrival_airport; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.routes.arrival_airport IS 'Code of airport of arrival';


--
-- Name: COLUMN routes.arrival_airport_name; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.routes.arrival_airport_name IS 'Name of airport of arrival';


--
-- Name: COLUMN routes.arrival_city; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.routes.arrival_city IS 'City of arrival';


--
-- Name: COLUMN routes.aircraft_code; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.routes.aircraft_code IS 'Aircraft code, IATA';


--
-- Name: COLUMN routes.duration; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.routes.duration IS 'Scheduled duration of flight';


--
-- Name: COLUMN routes.days_of_week; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.routes.days_of_week IS 'Days of week on which flights are scheduled';


--
-- PostgreSQL database dump complete
--

