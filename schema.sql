-- CREATE DATABASE incident_tracker;
-- CREATE ROLE incident_tracker WITH LOGIN PASSWORD 'password';
-- GRANT ALL ON DATABASE incident_tracker TO incident_tracker;

\c incident_tracker

-- DROP TABLE incident_unit;
-- DROP TABLE units;
-- DROP TABLE incidents;
-- DROP TABLE owners;
-- DROP TABLE agents;
-- DROP TABLE rules;
-- DROP TABLE categories;

BEGIN;

CREATE TABLE IF NOT EXISTS owners (
  owner_id serial PRIMARY KEY,
  name text NOT NULL,
  email text NOT NULL,
  phone text NOT NULL
);

CREATE TABLE IF NOT EXISTS agents (
  agent_id serial PRIMARY KEY,
  name text NOT NULL,
  email text NOT NULL,
  phone text NOT NULL
);

CREATE TABLE IF NOT EXISTS units (
  unit_id serial PRIMARY KEY,
  unit_number text NOT NULL,
  owner_id int REFERENCES owners (owner_id),
  agent_id int REFERENCES agents (agent_id),
  access_key text
);

CREATE TABLE IF NOT EXISTS rules (
  rule_id serial PRIMARY KEY,
  rule text NOT NULL
);

CREATE TABLE IF NOT EXISTS categories (
  category_id serial PRIMARY KEY,
  category text NOT NULL
);

CREATE TABLE IF NOT EXISTS incidents (
  incident_id serial PRIMARY KEY,
  incident_date TIMESTAMPTZ NOT NULL DEFAULT now(),
  category_id int REFERENCES categories (category_id),
  rule_id int REFERENCES rules (rule_id),
  guest_interaction boolean NOT NULL DEFAULT false,
  owner_interaction boolean NOT NULL DEFAULT false,
  contractor_interaction boolean NOT NULL DEFAULT false,
  interaction_conflict boolean NOT NULL DEFAULT false,
  notes text
);

CREATE TABLE IF NOT EXISTS incident_unit (
  incident_id int NOT NULL REFERENCES incidents (incident_id),
  unit_id int NOT NULL REFERENCES units (unit_id),
  PRIMARY KEY (incident_id, unit_id)
);

END;
