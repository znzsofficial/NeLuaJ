-- Shared desktop runner setup, before any loadfile-based behavioral fixture.
-- Run.java provides ASSETS from this script's tests/ location.
assert(ASSETS, "Run.java must initialize ASSETS")
package.path = ASSETS .. "?.lua;" .. package.path
local suite = assert(os.getenv("NELUAJ_TEST_SUITE"), "NELUAJ_TEST_SUITE is not set")
assert(loadfile(suite))()
