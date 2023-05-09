-- CREATE DATABASE incident_tracker;
-- CREATE ROLE incident_tracker WITH LOGIN PASSWORD 'password';
-- GRANT ALL ON DATABASE incident_tracker TO incident_tracker;

-- \c incident_tracker incident_tracker

-- DROP VIEW users_full;
-- DROP VIEW incidents_full;
-- DROP VIEW units_active;
-- DROP VIEW rules_active;
-- DROP VIEW categories_active;
-- DROP VIEW units_full;
-- DROP VIEW units_user;
-- DROP VIEW incident_notifications;
-- DROP TABLE incident_unit;
-- DROP TABLE user_unit;
-- DROP TABLE units;
-- DROP TABLE incident_photos;
-- DROP TABLE incident_notes;
-- DROP TABLE incidents;
-- DROP TABLE users;
-- DROP TABLE rules;
-- DROP TABLE categories;
-- DROP TABLE migration;
-- DROP FUNCTION get_login_code;
-- DROP FUNCTION validate_user;
-- DROP FUNCTION add_incident;
-- DROP FUNCTION add_incident_unit;
-- DROP FUNCTION add_note;
-- DROP FUNCTION delete_incident;
-- DROP FUNCTION restore_incident;
-- DROP FUNCTION add_user;
-- DROP FUNCTION edit_user;
-- DROP FUNCTION add_user_unit;

BEGIN;

CREATE TABLE IF NOT EXISTS migration (
  version text PRIMARY KEY
);

INSERT INTO migration values ('001');
INSERT INTO migration values ('002');
INSERT INTO migration values ('003');

CREATE TABLE IF NOT EXISTS users (
  user_id serial PRIMARY KEY,
  name text NOT NULL,
  email text NOT NULL UNIQUE,
  phone text NOT NULL default '',
  is_owner boolean NOT NULL DEFAULT false,
  is_agent boolean NOT NULL DEFAULT false,
  is_manager boolean NOT NULL DEFAULT false,
  is_board_member boolean NOT NULL DEFAULT false,
  login_code text NOT NULL DEFAULT ''
);

INSERT INTO users (name, email, is_manager) VALUES ('Manager', 'manager@incident-tracker.io', true);
INSERT INTO users (name, email, is_agent) VALUES ('Agent', 'agent@incident-tracker.io', true);
INSERT INTO users (name, email, is_owner) VALUES ('Owner', 'owner@incident-tracker.io', true);
INSERT INTO users (name, email, is_board_member) VALUES ('Board Member', 'board_member@incident-tracker.io', true);

CREATE OR REPLACE FUNCTION get_login_code(email text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  user_user_id int;
  user_login_code text;
BEGIN
  IF email != ''
    THEN SELECT INTO user_user_id u.user_id FROM users u WHERE u.email = get_login_code.email;
      IF user_user_id IS NULL
        THEN RETURN '';
      END IF;
  END IF;

  SELECT INTO user_login_code u.login_code FROM users u WHERE u.user_id = user_user_id;
  IF user_login_code = ''
    THEN SELECT INTO user_login_code floor(random()* (999999-100000 + 1) + 100000);
      UPDATE users SET login_code = user_login_code WHERE user_id = user_user_id;
  END IF;

  RETURN user_login_code;
END;
$$;

CREATE OR REPLACE FUNCTION validate_user(email text, login_code text)
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
  user_user_id int;
BEGIN
  IF email != '' AND login_code != ''
    THEN SELECT INTO user_user_id u.user_id FROM users u WHERE u.email = validate_user.email AND u.login_code = validate_user.login_code;
      IF user_user_id IS NOT NULL
        THEN UPDATE users SET login_code = '' WHERE user_id = user_user_id;
      END IF;
  END IF;

  RETURN user_user_id;
END;
$$;

CREATE TABLE IF NOT EXISTS units (
  unit_id serial PRIMARY KEY,
  unit_number text NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS user_unit (
  user_id int NOT NULL REFERENCES users (user_id),
  unit_id int NOT NULL REFERENCES units (unit_id),
  PRIMARY KEY (user_id, unit_id)
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
  user_id int REFERENCES users (user_id),
  manager int REFERENCES users (user_id),
  incident_date TIMESTAMPTZ NOT NULL DEFAULT now(),
  category_id int REFERENCES categories (category_id),
  rule_id int REFERENCES rules (rule_id),
  deleted boolean NOT NULL DEFAULT false,
  deleted_date TIMESTAMPTZ,
  created_date TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS incident_unit (
  incident_id int NOT NULL REFERENCES incidents (incident_id),
  unit_id int NOT NULL REFERENCES units (unit_id),
  PRIMARY KEY (incident_id, unit_id)
);

CREATE TABLE IF NOT EXISTS incident_photos (
  photo_id serial PRIMARY KEY,
  incident_id int REFERENCES incidents (incident_id),
  user_id int REFERENCES users (user_id),
  filename text NOT NULL,
  content bytea NOT NULL,
  content_type text NOT NULL,
  photo_date TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS incident_notes (
  note_id serial PRIMARY KEY,
  incident_id int REFERENCES incidents (incident_id),
  user_id int REFERENCES users (user_id),
  note text NOT NULL,
  note_date TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE VIEW units_full AS
  SELECT u.unit_id, u.unit_number, u.note,
    STRING_AGG(distinct '<a href="/user/' || uso.user_id || '">' || uso.name || '</a>' || ' - ' || uso.email || ' - ' || uso.phone, '<br />') as owners_short,
    STRING_AGG(distinct '<a href="/user/' || usa.user_id || '">' || usa.name || '</a>' || ' - ' || usa.email || ' - ' || usa.phone, '<br />') as agents_short,
    STRING_AGG(distinct $$<p>
      <form action="/remove_user_unit" method="post">
        $$ || '<a href="/user/' || uso.user_id || '">' || uso.name || '</a>' || ' - ' || uso.email || ' - ' || uso.phone || $$
        <input type="hidden" name="user_id" value="$$ || uu.user_id || $$">
        <input type="hidden" name="unit_id" value="$$ || uu.unit_id || $$">
        <input type="submit" value="Remove">
      </form></p>$$, ' ') as owners,
    STRING_AGG(distinct $$<p>
      <form action="/remove_user_unit" method="post">
        $$ || '<a href="/user/' || usa.user_id || '">' || usa.name || '</a>' || ' - ' || usa.email || ' - ' || usa.phone || $$
        <input type="hidden" name="user_id" value="$$ || uu.user_id || $$">
        <input type="hidden" name="unit_id" value="$$ || uu.unit_id || $$">
        <input type="submit" value="Remove">
      </form></p>$$, ' ') as agents
  FROM units u
    LEFT JOIN user_unit uu USING (unit_id)
    LEFT JOIN users uso ON uso.user_id=uu.user_id AND uso.is_owner
    LEFT JOIN users usa ON usa.user_id=uu.user_id AND usa.is_agent
  GROUP BY u.unit_id, u.unit_number;

CREATE VIEW users_full AS
  SELECT u.user_id, u.name, u.email, u.phone,
    CONCAT_WS(', ', CASE WHEN u.is_owner THEN 'owner' END, CASE WHEN u.is_agent THEN 'agent' END, CASE WHEN u.is_manager THEN 'manager' END, CASE WHEN u.is_board_member THEN 'board member' END) as user_type,
    STRING_AGG(distinct $$<a href='/unit/$$ || un.unit_id || $$'> $$ || un.unit_number || $$</a>$$, ', ') as units
  FROM users u
    LEFT JOIN user_unit uu USING (user_id)
    LEFT JOIN units un USING (unit_id)
  GROUP BY u.user_id, u.name, u.email, u.phone, u.is_owner, u.is_agent, u.is_manager, u.is_board_member;

CREATE VIEW incidents_full AS
SELECT i.incident_id,
    coalesce(MAX(ino.note_date), i.created_date) as update_date,
    us.user_id,
    us.name,
    us.email,
    us.phone,
    to_char(i.incident_date, 'YYYY-MM-DD') as incident_date,
    to_char(i.incident_date, 'HH24:MI') as incident_time,
    ARRAY_AGG(u.unit_number) as units,
    STRING_AGG(distinct $$<a href='/unit/$$ || u.unit_id || $$'> $$ || u.unit_number || $$</a>$$, ', ') as unit_number, c.category, r.rule,
    STRING_AGG(distinct $$<a href='/photo/$$ || ip.photo_id || $$'> $$ || ip.filename || $$</a>$$, ', ') as photos,
    (SELECT STRING_AGG($$<p class="incident-note">$$ || to_char(ino.note_date, 'YYYY-MM-DD HH24:MI') || ' ' || inou.name || ' wrote:' || $$<blockquote>$$ || ino.note || $$</blockquote></p>$$, ' ')
      FROM incident_notes ino LEFT JOIN users inou USING (user_id)
      WHERE ino.incident_id=i.incident_id) as notes,
    i.deleted
    FROM incidents i
      LEFT JOIN users us USING (user_id)
      LEFT JOIN categories c USING (category_id)
      LEFT JOIN rules r USING (rule_id)
      LEFT JOIN incident_unit iu USING (incident_id)
      LEFT JOIN units u USING (unit_id)
      LEFT JOIN incident_photos ip USING (incident_id)
      LEFT JOIN incident_notes ino USING (incident_id)
    GROUP BY i.incident_id, i.created_date, i.incident_date, us.user_id, us.name, us.email, us.phone, c.category, r.rule, i.deleted;

CREATE VIEW incident_notifications AS
  SELECT i.incident_id,
    m.name as manager_name, m.email as manager_email, m.phone as manager_phone,
    uuu.email,
    u.unit_number,
    c.category,
    r.rule,
    to_char(i.incident_date, 'YYYY-MM-DD') as incident_date,
    to_char(i.incident_date, 'HH24:MI') as incident_time,
    STRING_AGG($$<p class="incident-note">$$ || to_char(ino.note_date, 'YYYY-MM-DD HH24:MI') || ' ' || inou.name || ' wrote:' || $$<blockquote>$$ || ino.note || $$</blockquote></p>$$, ' ' ORDER BY ino.note_date) as notes
  FROM incidents i
    LEFT JOIN users m ON m.user_id=i.manager
    LEFT JOIN categories c USING (category_id)
    LEFT JOIN rules r USING (rule_id)
    LEFT JOIN incident_notes ino USING (incident_id)
      LEFT JOIN users inou ON ino.user_id=inou.user_id
    LEFT JOIN incident_unit iu USING (incident_id)
      LEFT JOIN units u USING (unit_id)
        LEFT JOIN user_unit uu ON uu.unit_id=u.unit_id
          LEFT JOIN users uuu ON uuu.user_id=uu.user_id AND uuu.is_agent
  GROUP BY i.incident_id, m.name, m.email, m.phone, uuu.email, u.unit_number, c.category, r.rule, i.incident_date;

CREATE VIEW units_active AS
  SELECT * FROM units u WHERE EXISTS( SELECT * FROM incidents i JOIN incident_unit iu USING(incident_id) WHERE iu.unit_id = u.unit_id AND deleted IS false )
    OR EXISTS( SELECT * FROM user_unit uu WHERE uu.unit_id=u.unit_id );

CREATE VIEW units_user AS
  SELECT u.*, us.* FROM units u JOIN user_unit uu USING (unit_id) JOIN users us USING (user_id);

CREATE VIEW rules_active AS
  SELECT * FROM rules r WHERE EXISTS( SELECT * FROM incidents i where i.rule_id = r.rule_id AND i.deleted is false);

CREATE VIEW categories_active AS
  SELECT * FROM categories c WHERE EXISTS( SELECT * FROM incidents i where i.category_id = c.category_id AND i.deleted is false);

CREATE OR REPLACE FUNCTION add_user(
  name text default '',
  email text default '',
  phone text default '',
  is_owner boolean default false,
  is_agent boolean default false,
  is_manager boolean default false,
  is_board_member boolean default false
)
  RETURNS int
  LANGUAGE plpgsql
as
$$
DECLARE
  add_user_id int;
BEGIN
  INSERT INTO users (name, email, phone, is_owner, is_agent, is_manager, is_board_member)
    VALUES (add_user.name, add_user.email, add_user.phone, add_user.is_owner, add_user.is_agent, add_user.is_manager, add_user.is_board_member)
    RETURNING user_id INTO add_user_id;
  RETURN add_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION edit_user(
  user_id int,
  name text default '',
  email text default '',
  phone text default '',
  is_owner boolean default false,
  is_agent boolean default false,
  is_manager boolean default false,
  is_board_member boolean default false
)
  RETURNS boolean
  LANGUAGE plpgsql
as
$$
DECLARE
BEGIN
  IF user_id=1 THEN is_manager=true; END IF;
  UPDATE users u SET
    name=edit_user.name,
    email=edit_user.email,
    phone=edit_user.phone,
    is_owner=edit_user.is_owner,
    is_agent=edit_user.is_agent,
    is_manager=edit_user.is_manager,
    is_board_member=edit_user.is_board_member
  WHERE u.user_id=edit_user.user_id;
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION add_user_unit(user_id int, unit text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  add_user_id int;
  add_unit_id int;
BEGIN
  IF unit != ''
    THEN SELECT INTO add_unit_id u.unit_id FROM units u WHERE u.unit_number = add_user_unit.unit;
      IF add_unit_id IS NULL
        THEN INSERT INTO units (unit_number) VALUES (add_user_unit.unit) RETURNING unit_id INTO add_unit_id;
      END IF;
  END IF;
  SELECT INTO add_user_id u.user_id from users u where u.user_id = add_user_unit.user_id;
  IF add_unit_id IS NULL OR add_user_id IS NULL
    THEN RETURN false;
  END IF;

  INSERT INTO user_unit VALUES (add_user_id, add_unit_id);
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION add_incident(
  incident_date text default null,
  category text default '',
  rule text default '',
  unit text default '',
  note text default '',
  user_id int default null
)
RETURNS int
LANGUAGE plpgsql
as
$$
DECLARE
  add_incident_date timestamptz;
  add_category_id int := NULL;
  add_rule_id int := NULL;
  add_unit_id int := NULL;
  manager_id int := NULL;
  add_incident_id int;
BEGIN
  IF incident_date is NOT NULL
    THEN add_incident_date := incident_date::timestamptz;
  ELSE add_incident_date := now();
  END IF;

  IF category != ''
    THEN SELECT INTO add_category_id c.category_id FROM categories c WHERE c.category = add_incident.category;
      IF add_category_id IS NULL
        THEN INSERT INTO categories (category) VALUES (add_incident.category) RETURNING category_id INTO add_category_id;
      END IF;
  END IF;

  IF rule != ''
    THEN SELECT INTO add_rule_id r.rule_id FROM rules r WHERE r.rule = add_incident.rule;
      IF add_rule_id IS NULL
        THEN INSERT INTO rules (rule) VALUES (add_incident.rule) RETURNING rule_id INTO add_rule_id;
      END IF;
  END IF;

  IF unit != ''
    THEN SELECT INTO add_unit_id u.unit_id FROM units u WHERE u.unit_number = add_incident.unit;
      IF add_unit_id IS NULL
        THEN INSERT INTO units (unit_number) VALUES (add_incident.unit) RETURNING unit_id INTO add_unit_id;
      END IF;
  END IF;

  INSERT INTO incidents (incident_date, category_id, rule_id, user_id)
    VALUES (add_incident_date, add_category_id, add_rule_id, user_id)
    RETURNING incident_id INTO add_incident_id;
  IF add_unit_id is NOT NULL THEN INSERT INTO incident_unit VALUES (add_incident_id, add_unit_id); END IF;

  INSERT INTO incident_notes (incident_id, note, user_id)
    VALUES (add_incident_id, add_incident.note, user_id);

  SELECT INTO manager_id u.user_id FROM users u WHERE u.user_id=add_incident.user_id and u.is_manager;
  IF manager_id is NOT NULL THEN UPDATE incidents SET manager=manager_id WHERE incidents.incident_id=add_incident_id; END IF;

  RETURN add_incident_id;
END;
$$;

CREATE OR REPLACE FUNCTION edit_incident(
  incident_id int,
  incident_date text default null,
  category text default '',
  rule text default '',
  user_id int default null
)
RETURNS boolean
LANGUAGE plpgsql
as
$$
DECLARE
  edit_incident_date timestamptz;
  edit_category_id int := NULL;
  edit_rule_id int := NULL;
  manager_id int := NULL;
BEGIN
  IF incident_date is NOT NULL
    THEN edit_incident_date := incident_date::timestamptz;
  ELSE edit_incident_date := now();
  END IF;

  IF category != ''
    THEN SELECT INTO edit_category_id c.category_id FROM categories c WHERE c.category = edit_incident.category;
      IF edit_category_id IS NULL
        THEN INSERT INTO categories (category) VALUES (edit_incident.category) RETURNING category_id INTO edit_category_id;
      END IF;
  END IF;

  IF rule != ''
    THEN SELECT INTO edit_rule_id r.rule_id FROM rules r WHERE r.rule = edit_incident.rule;
      IF edit_rule_id IS NULL
        THEN INSERT INTO rules (rule) VALUES (edit_incident.rule) RETURNING rule_id INTO edit_rule_id;
      END IF;
  END IF;

  SELECT INTO manager_id u.user_id FROM users u WHERE u.user_id=edit_incident.user_id and u.is_manager;
  IF manager_id is NOT NULL THEN UPDATE incidents SET manager=manager_id WHERE incidents.incident_id=edit_incident.incident_id; END IF;

  UPDATE incidents SET incident_date=edit_incident_date, category_id=edit_category_id, rule_id=edit_rule_id
    WHERE incidents.incident_id=edit_incident.incident_id;

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION delete_incident(incident_id int)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
BEGIN
  UPDATE incidents i SET deleted=true, deleted_date=now() WHERE i.incident_id=delete_incident.incident_id and i.deleted is false;
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION restore_incident(incident_id int)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
BEGIN
  UPDATE incidents i SET deleted=false, deleted_date=NULL WHERE i.incident_id=restore_incident.incident_id and i.deleted is true;
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION add_incident_unit(incident_id int, unit text, user_id int)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  add_incident_id int;
  add_unit_id int;
  manager_id int;
BEGIN 
  SELECT INTO manager_id u.user_id FROM users u WHERE u.user_id=add_incident_unit.user_id and u.is_manager;

  IF unit != ''
    THEN SELECT INTO add_unit_id u.unit_id FROM units u WHERE u.unit_number = add_incident_unit.unit;
      IF add_unit_id IS NULL
        THEN INSERT INTO units (unit_number) VALUES (add_incident_unit.unit) RETURNING unit_id INTO add_unit_id;
      END IF;
  END IF;
  SELECT INTO add_incident_id i.incident_id from incidents i where i.incident_id = add_incident_unit.incident_id;
  IF add_unit_id IS NULL OR add_incident_id IS NULL OR manager_id is NULL
    THEN RETURN false;
  END IF;

  UPDATE incidents SET manager=manager_id WHERE incidents.incident_id=add_incident_id;
  INSERT INTO incident_unit VALUES (add_incident_id, add_unit_id);
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION add_note(incident_id int, note text, user_id int)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  add_incident_id int;
  manager_id int;
BEGIN
  SELECT INTO add_incident_id i.incident_id from incidents i where i.incident_id = add_note.incident_id;
  IF add_incident_id IS NULL
    THEN RETURN false;
  END IF;

  IF note != ''
    THEN
      INSERT INTO incident_notes (incident_id, note, user_id) VALUES (add_incident_id, add_note.note, add_note.user_id);
      RETURN FOUND;
  END IF;

  SELECT INTO manager_id u.user_id FROM users u WHERE u.user_id=add_incident.user_id and u.is_manager;
  IF manager_id is NOT NULL THEN UPDATE incidents SET manager=manager_id WHERE incidents.incident_id=add_incident_id; END IF;

  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION edit_unit(
  unit_id int,
  note text default ''
)
  RETURNS boolean
  LANGUAGE plpgsql
as
$$
DECLARE
BEGIN
  UPDATE units u SET
    note=edit_unit.note
  WHERE u.unit_id=edit_unit.unit_id;
  RETURN FOUND;
END;
$$;

COMMIT;
