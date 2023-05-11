BEGIN;

INSERT INTO migration values ('004');

DROP VIEW units_full;

CREATE VIEW units_full AS
  SELECT * FROM (
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
  GROUP BY u.unit_id, u.unit_number) u
  WHERE (agents IS NOT NULL OR owners IS NOT NULL);

COMMIT;
