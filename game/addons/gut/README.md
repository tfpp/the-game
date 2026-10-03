# Vendored GUT

This project keeps GUT version lookups offline. The local patch in
`update_detector.gd` makes `fetch_remote_file()` return `OK` and emit
`download_completed` deferred, without making an HTTP request. This covers automatic
editor checks, the editor's manual Check for Update action, and CLI `-gcheck_update`.
Local and previously cached version metadata still support compatibility checks.
No GitHub token is needed; test error tracking remains enabled.

Preserve this patch when updating GUT. Regression coverage lives in
`tests/features/changelog/test_gut_updates.gd`. Normal test configuration remains in
`.gutconfig.json`; this is not a test-runner configuration option.
