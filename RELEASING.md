# Releasing

This repo uses SemVer tags (`vMAJOR.MINOR.PATCH`) and keeps human-readable notes in `CHANGELOG.md`.

## Release checklist

1. Ensure your working tree is clean:

   ```bash
   git status
   ```

2. Update `CHANGELOG.md`:

   - Move items from **Unreleased** into a new version section.
   - Use today’s date in `YYYY-MM-DD` format.

3. Run quick validation:

   ```bash
   bash -n download_docker_model.sh
   ```

4. Commit the release notes and code:

   ```bash
   git add -A
   git commit -m "Release vX.Y.Z"
   ```

5. Create an annotated tag and push it:

   ```bash
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin main --tags
   ```

6. Create a GitHub Release:
   - Title: `vX.Y.Z`
   - Notes: paste the matching section from `CHANGELOG.md`

