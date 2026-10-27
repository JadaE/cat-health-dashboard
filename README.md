# Pet Health Dashboard

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

## People and pets
The two-person picker uses generic labels (`Person A` = `persona`, `Person B` = `personb`); edit `PEOPLE` and the two buttons in `src/app.html` to use real names. Pets are not hard-coded: they are added in the app and stored in the data collection.

## Not included
- `secret-config.json` (real site slug, path token, collection name), `site/` build output, `.herenow/`.
- All logged data (weights, symptoms, vet visits, appointments, cat names): it lives in the here.now collection, not in this repo.
- Test screenshots.
