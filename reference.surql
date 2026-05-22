--  .d8888b.                                             888 8888888b.  888888b.
-- d88P  Y88b                                            888 888  'Y88b 888  '88b
-- Y88b.                                                 888 888    888 888  .88P
--  'Y888b.   888  888 888d888 888d888  .d88b.   8888b.  888 888    888 8888888K.
--     'Y88b. 888  888 888P'   888P'   d8P  Y8b     '88b 888 888    888 888  'Y88b
--       '888 888  888 888     888     88888888 .d888888 888 888    888 888    888
-- Y88b  d88P Y88b 888 888     888     Y8b.     888  888 888 888  .d88P 888   d88P
--  'Y8888P'   'Y88888 888     888      'Y8888  'Y888888 888 8888888P'  8888888P'
--
-- Welcome to SurrealDB, a multi-model database combining document, graph,
-- relational, time-series and vector capabilities in one system, all powered
-- by SurrealQL. Use it to build AI agents, real-time and event-driven systems,
-- knowledge graphs, as a backend, a BaaS, or embed it directly into your apps
-- One engine, every model.
--
-- Learn more at https://surrealdb.com/docs/surrealdb/introduction/start
--
-- *****************************************************************************

-- ------------------------------------------------------------
-- CRUD

CREATE user:martin CONTENT { name: "martin" };
CREATE user:ignacio CONTENT { name: "ignacio" };
CREATE user:tobie; user:jaime;

SELECT * FROM user;

UPDATE user:martin SET lastname = "schaer";

DELETE user:foo;

-- ------------------------------------------------------------
-- Relations through record links (simple, no metadata)
-- Create teams
CREATE team:green SET name = "Green";
CREATE team:red SET name = "Red";
UPDATE user:martin SET team = team:green;

SELECT id, name, team.name FROM user;
-- Show all properties inside team
SELECT id, name, team.* FROM user;

-- ------------------------------------------------------------
-- Relations through graph edges (can containe metadata)
RELATE user:martin->plays_for->team:green SET since = d'2025-10-23';
RELATE user:ignacio->plays_for->team:green;
RELATE user:tobie->plays_for->team:red;

SELECT *, ->plays_for->team as team FROM user;

// To learn more, go to SurrealDB University Fundamentals course:
// https://surrealdb.com/learn/fundamentals

-- ------------------------------------------------------------
-- Graph queries

// We'll create a graph and run different graph queries 
{
	CREATE document:doc_1;
	CREATE document:doc_2;
	CREATE category:important;
	CREATE tag:red;
	CREATE tag:blue;
	CREATE container:parent_folder;
	CREATE container:folder_1;

	RELATE document:doc_1->in_category->category:important;

	RELATE document:doc_1->has_tag->tag:red;
	RELATE document:doc_1->has_tag->tag:blue;
	RELATE document:doc_2->has_tag->tag:red;

	RELATE container:folder_1->stored_in->container:parent_folder;
	RELATE document:doc_1->stored_in->container:folder_1;
	RELATE document:doc_2->stored_in->container:parent_folder;
};

"Docs by category:";
SELECT *, <-in_category<-document AS docs FROM category;

"Docs by tag:";
SELECT *, <-has_tag<-document AS docs FROM tag;

"Container relations:";
-- Hint to visualize the graph:
-- 1. Select the query below
-- 2. Click "Run selection"
-- 3. Change "Combined" to "Graph"
SELECT *, <->stored_in AS relations FROM container FETCH relations;

"Related nodes by document:";
SELECT *, ->?->? AS related FROM document WHERE ;

"Recursive document path (fixed levels):";
SELECT *,
	@.{1}(->stored_in->?) AS cont1,
	@.{2}(->stored_in->?) AS cont2,
	@.{3}(->stored_in->?) AS cont3
FROM document;

"Recursive document path:";
SELECT @.{..}.{
	id,
	container: ->stored_in->container.@
} FROM document;

SELECT *, ->?->? FROM document;


-- ------------------------------------------------------------
-- Recursive query

{
	CREATE |node:1..10|;

	FOR $node IN SELECT * FROM node {
	LET $next = type::record("node", $node.id.id() + 1);
		RELATE $node->edge->$next SET read = rand::bool();
	};
};

"Recursive with filters:";
SELECT @.{1..6}.{
	id,
	next: ->edge[WHERE read = true]->node.@
} FROM node;


-- ------------------------------------------------------------
-- Collect with filter

{
	DELETE a, edge;

	CREATE a:1 SET bool = true;
	CREATE a:2 SET bool = true;
	CREATE a:3 SET bool = true;
	CREATE a:4 SET bool = false;
	CREATE a:5 SET bool = true;

	RELATE a:1->edge->a:2;
	RELATE a:2->edge->a:3;
	RELATE a:3->edge->a:4;
	RELATE a:4->edge->a:5;

	RETURN a:1.{..+collect+inclusive}
				(->edge->a[?bool]);
};

// To learn more about graph queries, go to the Using SurrealDB as a Graph Database page:
// https://surrealdb.com/docs/surrealdb/models/graph
-- Prepare the table
{
	DEFINE TABLE documents;
	DEFINE FIELD text ON documents TYPE string;
	DEFINE FIELD embedding ON documents TYPE array<float, 4>;
};

-- Vector index
-- Reference: https://surrealdb.com/docs/surrealdb/models/vector
DEFINE INDEX OVERWRITE documents_vec_index
	ON TABLE documents
	FIELDS embedding
	HNSW DIMENSION 4 DIST COSINE TYPE F32;

-- Add some documents with their embeddings
{
	CREATE documents CONTENT { text: "foo", embedding: [1f, 2f, 3f, 4f] };
	CREATE documents CONTENT { text: "bar", embedding: [2f, 2f, 2f, 2f] };
	CREATE documents CONTENT { text: "zar", embedding: [5f, 4f, 3f, 2f] };
};

-- Search query
LET $vector = [1f, 1f, 1f, 1f];

SELECT
	*,
	// knn() uses the distance function from the index
	(1 - vector::distance::knn()) AS score
	// while the following gets computed independently from the index
	// vector::similarity::cosine(embedding, $vector) AS similarity
	OMIT embedding // ignore the embedding in the result
	FROM documents
	WHERE embedding <|2,40|> $vector;

-- This shows the index, in the 'indexes' attribute
-- INFO FOR TABLE documents;


-- ------------------------------------------------------------
-- Functions
// The above search query can be turned into a function for ease of use


DEFINE FUNCTION OVERWRITE fn::search($vector: array<float>) {
	RETURN SELECT
		*,
		(1 - vector::distance::knn()) AS score
	OMIT embedding
	FROM documents
	WHERE embedding <|2,40|> $vector;
};

RETURN fn::search([1f, 2f, 3f, 4f]);

-- Congratulations, you've finished the onboarding!
-- Get your certificate by completing the SurrealDB University Fundamentals
-- See more examples in:
-- https://surrealdb.com/docs/labs?filters=demos%2Cexamples%2Csurrealdb+official

-- ------------------------------------------------------------
-- 8. SESSION INSPECTION
--
-- After authenticating, SurrealDB populates several read-only
-- parameters that can be queried to inspect the current session.
-- ------------------------------------------------------------

-- $session contains metadata about the current connection
SELECT * FROM $session;

-- $token contains the JWT claims used to establish the session
SELECT * FROM $token;

-- $auth points to the record of the authenticated record user
-- (NONE when authenticated as a system user)
SELECT * FROM $auth;

-- Practical use: check when the current session expires
SELECT exp FROM $session;

// To learn more about authentication in SurrealDB, visit:
// https://surrealdb.com/docs/learn/security/authentication/authentication

DEFINE TABLE OVERWRITE page SCHEMAFULL;

DEFINE FIELD OVERWRITE path         ON page TYPE string;
DEFINE FIELD OVERWRITE collection   ON page TYPE string;  -- e.g. "doc-surrealql", "doc-sdk-javascript"
DEFINE FIELD OVERWRITE title        ON page TYPE string;
DEFINE FIELD OVERWRITE description  ON page TYPE string;
DEFINE FIELD OVERWRITE breadcrumb   ON page TYPE string;  -- "SurrealQL > Statements > SELECT"
DEFINE FIELD OVERWRITE content      ON page TYPE string;  -- plain text, no code blocks
DEFINE FIELD OVERWRITE content_hash ON page TYPE string;  -- SHA-256 for incremental re-indexing
DEFINE FIELD OVERWRITE embedding    ON page TYPE array<float>;  -- 4D here; 1536D in production
DEFINE FIELD OVERWRITE date         ON page TYPE datetime DEFAULT time::now();

-- Unique path index lets the indexer UPSERT by URL
DEFINE INDEX OVERWRITE page_path_unique ON page FIELDS path UNIQUE CONCURRENTLY;
-- Collection index speeds up collection-filtered queries
DEFINE INDEX OVERWRITE page_collection  ON page FIELDS collection CONCURRENTLY;

-- BM25 full-text indexes, one per searchable field.
-- BM25(1.2, 0.75): k1=1.2 controls term-frequency saturation,
--                  b=0.75 controls document-length normalisation.
-- Field weights used at query time (see query-2.surql):
--   title (25) > path (15) > breadcrumb (10) > description (8) > content (3)
DEFINE INDEX OVERWRITE page_ft_title       ON page FIELDS title       FULLTEXT ANALYZER simple BM25(1.2, 0.75) CONCURRENTLY;
DEFINE INDEX OVERWRITE page_ft_breadcrumb  ON page FIELDS breadcrumb  FULLTEXT ANALYZER simple BM25(1.2, 0.75) CONCURRENTLY;
DEFINE INDEX OVERWRITE page_ft_description ON page FIELDS description FULLTEXT ANALYZER simple BM25(1.2, 0.75) CONCURRENTLY;
DEFINE INDEX OVERWRITE page_ft_content     ON page FIELDS content     FULLTEXT ANALYZER simple BM25(1.2, 0.75) CONCURRENTLY;
DEFINE INDEX OVERWRITE page_ft_path        ON page FIELDS path        FULLTEXT ANALYZER simple BM25(1.2, 0.75) CONCURRENTLY;

-- HNSW index for approximate nearest-neighbour vector search.
-- DIST COSINE is the standard metric for normalised text embeddings.
DEFINE INDEX OVERWRITE page_embedding_hnsw ON page FIELDS embedding
    HNSW DIMENSION 4 DIST COSINE CONCURRENTLY;


-- ------------------------------------------------------------
-- section table
--
-- One record per H2 heading within a page. Enables deep-linking
-- to specific sections and independent ranking of section content.
-- The `page` field is a record link with cascade delete, so
-- removing a page automatically removes all its sections.
-- ------------------------------------------------------------

DEFINE TABLE OVERWRITE section SCHEMAFULL;

DEFINE FIELD OVERWRITE page         ON section TYPE record<page>
    REFERENCE ON DELETE CASCADE;
DEFINE FIELD OVERWRITE anchor       ON section TYPE string;  -- URL fragment, e.g. "record-ranges"
DEFINE FIELD OVERWRITE depth        ON section TYPE int;     -- heading depth (always 2)
DEFINE FIELD OVERWRITE title        ON section TYPE string;
DEFINE FIELD OVERWRITE breadcrumb   ON section TYPE string;  -- page breadcrumb + " > " + section title
DEFINE FIELD OVERWRITE content      ON section TYPE string;
DEFINE FIELD OVERWRITE content_hash ON section TYPE string;
DEFINE FIELD OVERWRITE embedding    ON section TYPE array<float>;
DEFINE FIELD OVERWRITE date         ON section TYPE datetime DEFAULT time::now();

-- Unique (page, anchor) prevents duplicate sections per page
DEFINE INDEX OVERWRITE section_page   ON section FIELDS page CONCURRENTLY;
DEFINE INDEX OVERWRITE section_anchor ON section FIELDS page, anchor UNIQUE CONCURRENTLY;

-- Sections search title (25), breadcrumb (10), and content (3)
DEFINE INDEX OVERWRITE section_ft_title      ON section FIELDS title      FULLTEXT ANALYZER simple BM25(1.2, 0.75) CONCURRENTLY;
DEFINE INDEX OVERWRITE section_ft_breadcrumb ON section FIELDS breadcrumb FULLTEXT ANALYZER simple BM25(1.2, 0.75) CONCURRENTLY;
DEFINE INDEX OVERWRITE section_ft_content    ON section FIELDS content    FULLTEXT ANALYZER simple BM25(1.2, 0.75) CONCURRENTLY;

DEFINE INDEX OVERWRITE section_embedding_hnsw ON section FIELDS embedding
    HNSW DIMENSION 4 DIST COSINE CONCURRENTLY;

// To learn more about the search schema used here, see:
// https://surrealdb.com/docs/reference/query-language/statements/define/indexes

DELETE FROM page WHERE id IN $stale_page_ids;

CREATE page:select CONTENT {
    path:         "/docs/surrealql/statements/select",
    collection:   "doc-surrealql",
    title:        "SELECT",
    description:  "The SELECT statement can be used to retrieve and filter data from tables and records.",
    breadcrumb:   "SurrealQL > Statements > SELECT",
    content:      "The SELECT statement retrieves records from one or more tables. You can filter results with WHERE, sort with ORDER BY, limit with LIMIT, and traverse graph edges inline.",
    content_hash: "hash-select-v1",
    embedding:    [0.9, 0.2, 0.05, 0.15]
};

CREATE page:define_table CONTENT {
    path:         "/docs/surrealql/statements/define/table",
    collection:   "doc-surrealql",
    title:        "DEFINE TABLE",
    description:  "The DEFINE TABLE statement defines the schema for a table, including field types, indexes, and permissions.",
    breadcrumb:   "SurrealQL > Statements > DEFINE > TABLE",
    content:      "Use DEFINE TABLE to declare a table as SCHEMAFULL or SCHEMALESS, define field types, set up indexes, and configure access permissions using the PERMISSIONS clause.",
    content_hash: "hash-define-table-v1",
    embedding:    [0.15, 0.9, 0.1, 0.3]
};

CREATE page:authentication CONTENT {
    path:         "/docs/surrealdb/security/authentication",
    collection:   "doc-surrealdb",
    title:        "Authentication",
    description:  "SurrealDB supports system users (RBAC) and record users (custom signup/signin logic).",
    breadcrumb:   "SurrealDB > Security > Authentication",
    content:      "SurrealDB has two authentication models: system users defined with DEFINE USER and governed by RBAC roles, and record users defined with DEFINE ACCESS that support custom signup and signin logic and fine-grained permissions.",
    content_hash: "hash-auth-v1",
    embedding:    [0.1, 0.2, 0.95, 0.05]
};

CREATE page:indexes CONTENT {
    path:         "/docs/surrealql/statements/define/indexes",
    collection:   "doc-surrealql",
    title:        "Indexes",
    description:  "SurrealDB supports unique, full-text (BM25), and vector (HNSW) indexes for fast lookups and search.",
    breadcrumb:   "SurrealQL > Statements > DEFINE > INDEX",
    content:      "DEFINE INDEX creates an index on one or more fields. Use UNIQUE for uniqueness constraints, FULLTEXT with BM25 for full-text search, and HNSW for approximate nearest-neighbour vector search with cosine or euclidean distance.",
    content_hash: "hash-indexes-v1",
    embedding:    [0.25, 0.55, 0.05, 0.9]
};

CREATE page:relate CONTENT {
    path:         "/docs/surrealql/statements/relate",
    collection:   "doc-surrealql",
    title:        "RELATE",
    description:  "The RELATE statement creates a graph edge between two records, enabling graph traversal queries.",
    breadcrumb:   "SurrealQL > Statements > RELATE",
    content:      "RELATE creates a directed edge between two records using the syntax RELATE source->edge->target. You can store metadata on the edge and traverse it with SELECT ->edge->target FROM source.",
    content_hash: "hash-relate-v1",
    embedding:    [0.75, 0.35, 0.05, 0.1]
};


-- ------------------------------------------------------------
-- Sample sections
--
-- Sections belong to pages via record link and are identified
-- by a (page, anchor) pair. The URL is page.path + "#" + anchor.
-- ------------------------------------------------------------

CREATE section:select_basic CONTENT {
    page:         page:select,
    anchor:       "basic-usage",
    depth:        2,
    title:        "Basic usage",
    breadcrumb:   "SurrealQL > Statements > SELECT > Basic usage",
    content:      "The simplest SELECT query retrieves all fields from all records in a table: SELECT * FROM person. You can project specific fields: SELECT name, age FROM person.",
    content_hash: "hash-select-basic-v1",
    embedding:    [0.95, 0.1, 0.0, 0.05]
};

CREATE section:select_where CONTENT {
    page:         page:select,
    anchor:       "filtering-with-where",
    depth:        2,
    title:        "Filtering with WHERE",
    breadcrumb:   "SurrealQL > Statements > SELECT > Filtering with WHERE",
    content:      "Use the WHERE clause to filter records by conditions. Supports comparison operators, AND, OR, NOT, and nested conditions.",
    content_hash: "hash-select-where-v1",
    embedding:    [0.85, 0.15, 0.0, 0.1]
};

CREATE section:define_table_permissions CONTENT {
    page:         page:define_table,
    anchor:       "permissions",
    depth:        2,
    title:        "Table permissions",
    breadcrumb:   "SurrealQL > Statements > DEFINE > TABLE > Table permissions",
    content:      "The PERMISSIONS clause restricts what record users can do. Use WHERE id = $auth.id to limit each user to their own records. System users are not affected by table permissions.",
    content_hash: "hash-define-table-perms-v1",
    embedding:    [0.1, 0.6, 0.7, 0.05]
};

CREATE section:auth_record_access CONTENT {
    page:         page:authentication,
    anchor:       "record-users",
    depth:        2,
    title:        "Record users",
    breadcrumb:   "SurrealDB > Security > Authentication > Record users",
    content:      "Record users are defined with DEFINE ACCESS TYPE RECORD. You provide a SIGNUP expression that creates a new user record and a SIGNIN expression that validates credentials.",
    content_hash: "hash-auth-record-v1",
    embedding:    [0.1, 0.3, 0.95, 0.05]
};

CREATE section:indexes_hnsw CONTENT {
    page:         page:indexes,
    anchor:       "vector-hnsw",
    depth:        2,
    title:        "Vector indexes (HNSW)",
    breadcrumb:   "SurrealQL > Statements > DEFINE > INDEX > Vector indexes (HNSW)",
    content:      "HNSW (Hierarchical Navigable Small World) is an approximate nearest-neighbour algorithm. Specify HNSW DIMENSION N DIST COSINE. Query with the KNN operator: WHERE embedding <|k,ef|> $vector.",
    content_hash: "hash-indexes-hnsw-v1",
    embedding:    [0.3, 0.5, 0.0, 0.95]
};

CREATE section:relate_traversal CONTENT {
    page:         page:relate,
    anchor:       "graph-traversal",
    depth:        2,
    title:        "Graph traversal",
    breadcrumb:   "SurrealQL > Statements > RELATE > Graph traversal",
    content:      "After creating edges with RELATE, traverse them in SELECT using arrow syntax: SELECT ->knows->person FROM person:alice. Use <- for inbound edges and <-> for both directions.",
    content_hash: "hash-relate-traversal-v1",
    embedding:    [0.8, 0.2, 0.0, 0.1]
};

FOR $data IN (SELECT * FROM naive_movie) {
    LET $movie = CREATE movie SET
        awards = $data.Awards,
		oscars_won = fn::get_oscars(awards),
        box_office = IF $data.BoxOffice = 'N/A' { NONE } ELSE { <int>string::replace(string::replace($data.BoxOffice, '$', ''), ',', '') },
        dvd = IF $data.DVD = 'N/A' { NONE } ELSE { fn::date_to_datetime($data.DVD) },
        genres = $data.Genre.split(', '),
        languages = string::split($data.Language, ', '),
        plot = $data.Plot,
        poster = $data.Poster,
        rated = $data.Rated,
        imdb_rating = fn::get_imdb($data.Ratings),
        rt_rating =   fn::get_rt($data.Ratings),
        metacritic_rating = fn::get_metacritic($data.Ratings),
        released = fn::date_to_datetime($data.Released),
        runtime = <duration>string::replace($data.Runtime, ' min', 'm'),
        title = $data.Title;

    FOR $name IN string::split($data.Actors, ", ") {
        LET $actor = (SELECT * FROM ONLY person WHERE name = $name LIMIT 1);
        LET $actor = IF $actor IS NONE {
            (CREATE ONLY person SET name = $name, roles += "actor")
        } ELSE {
            IF "actor" NOT IN $actor.roles {
                UPDATE $actor SET roles += "actor"
            };
            $actor
        };
        RELATE $actor->starred_in->$movie;
    };

    FOR $name IN string::split($data.Director, ", ") {
        LET $director = (SELECT * FROM ONLY person WHERE name = $name LIMIT 1);
        LET $director = IF $director IS NONE {
            (CREATE ONLY person SET name = $name, roles += "director")
        } ELSE {
            IF "director" NOT IN $director.roles {
                UPDATE $director SET roles += "director"
            };
            $director
        };
        RELATE $director->directed->$movie;
    };

    FOR $name IN string::split($data.Writer, ", ") {
        LET $writer = (SELECT * FROM ONLY person WHERE name = $name LIMIT 1);
        LET $writer = IF $writer IS NONE {
            (CREATE ONLY person SET name = $name, roles += "writer")
        } ELSE {
            IF "writer" NOT IN $writer.roles {
                UPDATE $writer SET roles += "writer"
            };
            $writer
        };
        RELATE $writer->wrote->$movie;
    };


    FOR $country_name IN string::split($data.Country, ', ') {
        LET $country = (SELECT * FROM ONLY country WHERE name = $country_name LIMIT 1);
        LET $country = IF $country IS NONE {
            (CREATE ONLY country SET name = $country_name)
        } ELSE {
            $country
        };
        RELATE $country->has_movie->$movie;
    };
};

SELECT *,
    <-wrote<-person.name AS writers,
    <-starred_in<-person.name AS actors,
    <-directed<-person.name AS directors,
    <-has_movie<-country.name AS made_in,
    math::mean([imdb_rating, metacritic_rating, rt_rating][WHERE $this != NONE]) AS average_score
    FROM movie;

// 250 vs. about 228 
RETURN [
	count(SELECT id FROM movie),
	count(SELECT metacritic_rating FROM movie WHERE metacritic_rating != NONE)
];