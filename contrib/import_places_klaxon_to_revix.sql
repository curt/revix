INSERT INTO	places (
	id,
	uri,
	url,
	origin,
	"name",
	slug,
	coordinates,
	altitude,
	"content",
	content_html,
	inserted_at,
	updated_at
)
SELECT
	utils.generate_id_from_guid(p.id::text) id,
	'http://localhost:4000/l/' || utils.generate_id_from_guid(p.id::text) uri,
	'http://localhost:4000/l/' || utils.generate_id_from_guid(p.id::text) url,
	'local' origin,
	p.title "name",
	p.slug,
	ST_GeogFromText('POINT(' || p.lon || ' ' || p.lat || ')') coordinates,
	p.ele altitude,
	p."source" "content",
	p.content_html,
	p.published_at inserted_at,
	p.updated_at
FROM
	klaxon.places p
WHERE
	p.published_at IS NOT NULL
