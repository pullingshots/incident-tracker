DROP view incidents_full;
DROP view units_user;

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


CREATE VIEW units_user AS
  SELECT u.*, us.* FROM units u JOIN user_unit uu USING (unit_id) JOIN users us USING (user_id);
