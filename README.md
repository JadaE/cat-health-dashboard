# Pet Health Dashboard

> 🤖 This project was created by [Grok Bot](https://cursor.com) from Cursor.

A small single-page web app for logging pet health: weight, food, water, litter box, behavior, symptoms, meds, vet visits and upcoming appointments, with a weight chart per pet. Data syncs between phones through a here.now Site Data collection and is cached offline in the browser.

- `src/app.html` the app, `src/assets/` icons, manifest and service worker.
- `tools/store.js` shared store and sync, `tools/build.py` builds a publishable `site/` from `src/` (needs a local `secret-config.json` with a path token and collection name; copy `secret-config.example.json` and fill in your own values), `tools/verify-no-secrets.sh` pre-publish check.
- `test/` Playwright tests (`npm install` in `test/`).

## Tests
```bash
cp secret-config.example.json secret-config.json   # fake values are fine for local tests
python3 tools/build.py                              # builds site/ (git-ignored)
(cd test && npm install)
node test/mock-server.js 8787 &                     # local stand-in for the here.now Site Data endpoint
node test/two-phones.js && node test/appts.js       # needs Google Chrome at /usr/bin/google-chrome
```
`test/check-cats.js` checks a live deployment: `APP_URL=https://... CAT_NAMES='Name 1,Name 2' node test/check-cats.js`.

## Rotating the collection name (tooling only)
`python3 tools/prepare-rotation.py [--token]` writes `.rotation/secret-config.next.json` (folder 0700, file 0600, git-ignored) with a new random collection name (and, with `--token`, a new path token), the old collection moved to `retired_collections`. The new values are never printed and `secret-config.json` is only read. `--check` confirms the file is present with private modes. `tools/build.py` lists retired collections in the manifest as owner-only and never puts them in the app; `tools/verify-no-secrets.sh` fails if a retired collection is publicly readable or appears in a served file. Switching to the new config and republishing is a separate, approved step.

Mode/rotation test suites (placeholder values, no network beyond localhost): `bash test/jc36-modes.sh && bash test/jc41-rotation.sh`.

## People and pets
The two-person picker uses generic labels (`Person A` = `persona`, `Person B` = `personb`); edit `PEOPLE` and the two buttons in `src/app.html` to use real names. Pets are not hard-coded: they are added in the app and stored in the data collection.

## Not included
- `secret-config.json` (real site slug, path token, collection name), `site/` build output, `.herenow/`.
- All logged data (weights, symptoms, vet visits, appointments, cat names): it lives in the here.now collection, not in this repo.
- Test screenshots.
