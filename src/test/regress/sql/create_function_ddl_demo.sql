CREATE FUNCTION check_foreign_key ()
	RETURNS trigger
	AS '/space/sda1/ibarwick/2ndquadrant_bdr/src/test/regress/refint.so'
	LANGUAGE C;