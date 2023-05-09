BEGIN;

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

INSERT INTO migration values ('003');

COMMIT;
