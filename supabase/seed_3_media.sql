insert into experience_media (experience_id, kind, license, alt_text, is_primary, position)
select id, 'placeholder', 'placeholder',
       short_description, true, 0
from experiences;

insert into experience_media (experience_id, kind, license, alt_text, is_primary, position)
select id, 'placeholder', 'placeholder', short_description, true, 0
from experiences
where source = 'catalog'
  and not exists (select 1 from experience_media m where m.experience_id = experiences.id);
