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
-- Name: flights_v; Type: VIEW; Schema: bookings; Owner: postgres
--

CREATE VIEW bookings.flights_v AS
SELECT f.flight_id,
       f.flight_no,
       f.scheduled_departure,
       timezone(dep.timezone, f.scheduled_departure) AS scheduled_departure_local,
       f.scheduled_arrival,
       timezone(arr.timezone, f.scheduled_arrival) AS scheduled_arrival_local,
       (f.scheduled_arrival - f.scheduled_departure) AS scheduled_duration,
       f.departure_airport,
       dep.airport_name AS departure_airport_name,
       dep.city AS departure_city,
       f.arrival_airport,
       arr.airport_name AS arrival_airport_name,
       arr.city AS arrival_city,
       f.status,
       f.aircraft_code,
       f.actual_departure,
       timezone(dep.timezone, f.actual_departure) AS actual_departure_local,
       f.actual_arrival,
       timezone(arr.timezone, f.actual_arrival) AS actual_arrival_local,
       (f.actual_arrival - f.actual_departure) AS actual_duration
FROM bookings.flights f,
     bookings.airports dep,
     bookings.airports arr
WHERE ((f.departure_airport = dep.airport_code) AND (f.arrival_airport = arr.airport_code));


ALTER TABLE bookings.flights_v OWNER TO postgres;

--
-- Name: VIEW flights_v; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON VIEW bookings.flights_v IS 'Flights (extended)';


--
-- Name: COLUMN flights_v.flight_id; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.flight_id IS 'Flight ID';


--
-- Name: COLUMN flights_v.flight_no; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.flight_no IS 'Flight number';


--
-- Name: COLUMN flights_v.scheduled_departure; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.scheduled_departure IS 'Scheduled departure time';


--
-- Name: COLUMN flights_v.scheduled_departure_local; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.scheduled_departure_local IS 'Scheduled departure time, local time at the point of departure';


--
-- Name: COLUMN flights_v.scheduled_arrival; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.scheduled_arrival IS 'Scheduled arrival time';


--
-- Name: COLUMN flights_v.scheduled_arrival_local; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.scheduled_arrival_local IS 'Scheduled arrival time, local time at the point of destination';


--
-- Name: COLUMN flights_v.scheduled_duration; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.scheduled_duration IS 'Scheduled flight duration';


--
-- Name: COLUMN flights_v.departure_airport; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.departure_airport IS 'Deprature airport code';


--
-- Name: COLUMN flights_v.departure_airport_name; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.departure_airport_name IS 'Departure airport name';


--
-- Name: COLUMN flights_v.departure_city; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.departure_city IS 'City of departure';


--
-- Name: COLUMN flights_v.arrival_airport; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.arrival_airport IS 'Arrival airport code';


--
-- Name: COLUMN flights_v.arrival_airport_name; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.arrival_airport_name IS 'Arrival airport name';


--
-- Name: COLUMN flights_v.arrival_city; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.arrival_city IS 'City of arrival';


--
-- Name: COLUMN flights_v.status; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.status IS 'Flight status';


--
-- Name: COLUMN flights_v.aircraft_code; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.aircraft_code IS 'Aircraft code, IATA';


--
-- Name: COLUMN flights_v.actual_departure; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.actual_departure IS 'Actual departure time';


--
-- Name: COLUMN flights_v.actual_departure_local; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.actual_departure_local IS 'Actual departure time, local time at the point of departure';


--
-- Name: COLUMN flights_v.actual_arrival; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.actual_arrival IS 'Actual arrival time';


--
-- Name: COLUMN flights_v.actual_arrival_local; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.actual_arrival_local IS 'Actual arrival time, local time at the point of destination';


--
-- Name: COLUMN flights_v.actual_duration; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights_v.actual_duration IS 'Actual flight duration';


--
-- PostgreSQL database dump complete
--
