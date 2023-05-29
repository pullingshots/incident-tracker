BEGIN;

INSERT INTO migration values ('005');

DROP VIEW users_full;

CREATE VIEW users_full AS
  SELECT u.user_id, u.name, u.email, u.phone, u.is_owner, u.is_agent, u.is_manager, u.is_board_member,
    CONCAT_WS(', ', CASE WHEN u.is_owner THEN 'owner' END, CASE WHEN u.is_agent THEN 'agent' END, CASE WHEN u.is_manager THEN 'manager' END, CASE WHEN u.is_board_member THEN 'board member' END) as user_type,
    CASE WHEN u.is_owner OR u.is_agent THEN
      STRING_AGG(distinct $$<a href='/unit/$$ || un.unit_id || $$'> $$ || un.unit_number || $$</a>$$, ', ')
      ELSE ''
      END as units
  FROM users u
    LEFT JOIN user_unit uu USING (user_id)
    LEFT JOIN units un USING (unit_id)
  GROUP BY u.user_id, u.name, u.email, u.phone, u.is_owner, u.is_agent, u.is_manager, u.is_board_member;

CREATE OR REPLACE FUNCTION get_login_code(email text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  user_user_id int;
  user_login_code text;
BEGIN
  IF email != ''
    THEN SELECT INTO user_user_id u.user_id FROM users u WHERE u.email = get_login_code.email
      AND (u.is_agent OR u.is_owner OR u.is_board_member OR u.is_manager);
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

END;
