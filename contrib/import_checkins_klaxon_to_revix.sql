INSERT INTO entries (
	id,
	uri,
	url,
	"type",
	"content",
	content_html,
	context,
	origin,
	published_at_utc,
	published_at_local,
	published_tz,
	starts_at_utc,
	starts_at_local,
	starts_tz,
	author_uri,
	place_uri,
	inserted_at,
	updated_at
)
SELECT
	utils.generate_id_from_guid(c.id::text) id,
	'http://localhost:4000/l/' || utils.generate_id_from_guid(p.id::text) || '/c/' || utils.generate_id_from_guid(c.id::text) uri,
	'http://localhost:4000/l/' || utils.generate_id_from_guid(p.id::text) || '/c/' || utils.generate_id_from_guid(c.id::text) url,
	'checkin' type,
	c.source content,
	c.content_html,
	'http://localhost:4000/l/' || utils.generate_id_from_guid(p.id::text) || '/c/' || utils.generate_id_from_guid(c.id::text) context,
	'local' origin,
	c.published_at published_at_utc,
	c.published_at published_at_local,
	'Etc/UTC' published_tz,
	c.checked_in_at starts_at_utc,
	c.checked_in_at starts_at_local,
	'Etc/UTC' starts_tz,
	'http://localhost:4000/u/' author_uri,
	'http://localhost:4000/l/' || utils.generate_id_from_guid(p.id::text) place_uri,
	c.inserted_at,
	c.updated_at
FROM
	klaxon.checkins c
INNER JOIN klaxon.places p ON
	c.place_id = p.id
WHERE
	c.status = 'published'
	AND p.status = 'published'
