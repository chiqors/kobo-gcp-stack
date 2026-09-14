# Rollback

Application rollback is permitted only when the previous image supports the
current database schema. If a migration is not backward compatible, restore
state into an isolated environment and follow the release-specific recovery
procedure instead of blindly starting the old image.

Keep the previous rendered configuration and image digests until verification
is complete. Do not roll media back independently of database state without an
incident-specific consistency assessment.
