-- RT#60660

SELECT * FROM public.bdr_regress_variables()
\gset

\c :writedb1


CREATE TABLE desync (
   id integer primary key not null,
   n1 integer not null
);

\d desync

SELECT pg_xlog_wait_remote_apply(pg_current_xlog_location(), 0);

-- basic builtin datatypes
\c :writedb2

\d desync

\c :writedb1

BEGIN;
SET LOCAL bdr.skip_ddl_replication = on;
SET LOCAL bdr.skip_ddl_locking = on;
ALTER TABLE desync ADD COLUMN dropme integer;
COMMIT;

BEGIN;
SET LOCAL bdr.skip_ddl_replication = on;
SET LOCAL bdr.skip_ddl_locking = on;
ALTER TABLE desync DROP COLUMN dropme;
COMMIT;

-- create natts=3 tuple on db1
--
-- This will fail to apply because natts of other side
-- is less than our natts.
INSERT INTO desync(id, n1) VALUES (1, 1);

SELECT * FROM desync ORDER BY id;

-- We cannot use a statement_timeout and wait for apply to prove
-- we're stuck here, because walsender connects/disconnects. But
-- a DDL lock attempt works.
-- This must ERROR not ROLLBACK
BEGIN;
SET LOCAL statement_timeout = '2s';
CREATE TABLE dummy_tbl(id integer);
ROLLBACK;

\c :writedb2

SELECT * FROM desync ORDER BY id;

-- create natts=2 tuple on db2
--
-- This should apply to writedb1 because we right-pad rows with low natts if
-- the other side col is dropped (or nullable)
INSERT INTO desync(id, n1) VALUES (2, 2);

SELECT pg_xlog_wait_remote_apply(pg_current_xlog_location(), 0);

-- This must ROLLBACK not ERROR
BEGIN;
SET LOCAL statement_timeout = '10s';
CREATE TABLE dummy_tbl(id integer);
ROLLBACK;

SELECT * FROM desync ORDER BY id;

-- But now if we make matching changes on our side, our natts should match
-- and we can apply the remote's tuple too. For kicks this time do in one
-- txn.
BEGIN;
SET LOCAL bdr.skip_ddl_replication = on;
SET LOCAL bdr.skip_ddl_locking = on;
ALTER TABLE desync ADD COLUMN dropme integer;
ALTER TABLE desync DROP COLUMN dropme;
COMMIT;

\c :writedb1

-- So now this side should apply too
SELECT pg_xlog_wait_remote_apply(pg_current_xlog_location(), 0);

-- This must ROLLBACK not ERROR
BEGIN;
SET LOCAL statement_timeout = '10s';
CREATE TABLE dummy_tbl(id integer);
ROLLBACK;

-- Yay!
SELECT * FROM desync ORDER BY id;

\c :writedb2
-- Yay! Again!
SELECT * FROM desync ORDER BY id;
