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

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: flights; Type: TABLE; Schema: bookings; Owner: postgres
--

CREATE TABLE bookings.flights (
    flight_id integer NOT NULL,
    flight_no character(6) NOT NULL,
    scheduled_departure timestamp with time zone NOT NULL,
    scheduled_arrival timestamp with time zone NOT NULL,
    departure_airport character(3) NOT NULL,
    arrival_airport character(3) NOT NULL,
    status character varying(20) NOT NULL,
    aircraft_code character(3) NOT NULL,
    actual_departure timestamp with time zone,
    actual_arrival timestamp with time zone,
    CONSTRAINT flights_check CHECK ((scheduled_arrival > scheduled_departure)),
    CONSTRAINT flights_check1 CHECK (((actual_arrival IS NULL) OR ((actual_departure IS NOT NULL) AND (actual_arrival IS NOT NULL) AND (actual_arrival > actual_departure)))),
    CONSTRAINT flights_status_check CHECK (((status)::text = ANY (ARRAY[('On Time'::character varying)::text, ('Delayed'::character varying)::text, ('Departed'::character varying)::text, ('Arrived'::character varying)::text, ('Scheduled'::character varying)::text, ('Cancelled'::character varying)::text])))
);


ALTER TABLE bookings.flights OWNER TO postgres;

--
-- Name: TABLE flights; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON TABLE bookings.flights IS 'Flights';


--
-- Name: COLUMN flights.flight_id; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights.flight_id IS 'Flight ID';


--
-- Name: COLUMN flights.flight_no; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights.flight_no IS 'Flight number';


--
-- Name: COLUMN flights.scheduled_departure; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights.scheduled_departure IS 'Scheduled departure time';


--
-- Name: COLUMN flights.scheduled_arrival; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights.scheduled_arrival IS 'Scheduled arrival time';


--
-- Name: COLUMN flights.departure_airport; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights.departure_airport IS 'Airport of departure';


--
-- Name: COLUMN flights.arrival_airport; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights.arrival_airport IS 'Airport of arrival';


--
-- Name: COLUMN flights.status; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights.status IS 'Flight status';


--
-- Name: COLUMN flights.aircraft_code; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights.aircraft_code IS 'Aircraft code, IATA';


--
-- Name: COLUMN flights.actual_departure; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights.actual_departure IS 'Actual departure time';


--
-- Name: COLUMN flights.actual_arrival; Type: COMMENT; Schema: bookings; Owner: postgres
--

COMMENT ON COLUMN bookings.flights.actual_arrival IS 'Actual arrival time';


--
-- Name: flights_flight_id_seq; Type: SEQUENCE; Schema: bookings; Owner: postgres
--

CREATE SEQUENCE bookings.flights_flight_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bookings.flights_flight_id_seq OWNER TO postgres;

--
-- Name: flights_flight_id_seq; Type: SEQUENCE OWNED BY; Schema: bookings; Owner: postgres
--

ALTER SEQUENCE bookings.flights_flight_id_seq OWNED BY bookings.flights.flight_id;


--
-- Name: flights flight_id; Type: DEFAULT; Schema: bookings; Owner: postgres
--

ALTER TABLE ONLY bookings.flights ALTER COLUMN flight_id SET DEFAULT nextval('bookings.flights_flight_id_seq'::regclass);


--
-- Name: flights flights_flight_no_scheduled_departure_key; Type: CONSTRAINT; Schema: bookings; Owner: postgres
--

ALTER TABLE ONLY bookings.flights
    ADD CONSTRAINT flights_flight_no_scheduled_departure_key UNIQUE (flight_no, scheduled_departure);


--
-- Name: flights flights_pkey; Type: CONSTRAINT; Schema: bookings; Owner: postgres
--

ALTER TABLE ONLY bookings.flights
    ADD CONSTRAINT flights_pkey PRIMARY KEY (flight_id);


--
-- Name: flights flights_aircraft_code_fkey; Type: FK CONSTRAINT; Schema: bookings; Owner: postgres
--

ALTER TABLE ONLY bookings.flights
    ADD CONSTRAINT flights_aircraft_code_fkey FOREIGN KEY (aircraft_code) REFERENCES bookings.aircrafts_data(aircraft_code);


--
-- Name: flights flights_arrival_airport_fkey; Type: FK CONSTRAINT; Schema: bookings; Owner: postgres
--

ALTER TABLE ONLY bookings.flights
    ADD CONSTRAINT flights_arrival_airport_fkey FOREIGN KEY (arrival_airport) REFERENCES bookings.airports_data(airport_code);


--
-- Name: flights flights_departure_airport_fkey; Type: FK CONSTRAINT; Schema: bookings; Owner: postgres
--

ALTER TABLE ONLY bookings.flights
    ADD CONSTRAINT flights_departure_airport_fkey FOREIGN KEY (departure_airport) REFERENCES bookings.airports_data(airport_code);


--
-- PostgreSQL database dump complete
--

