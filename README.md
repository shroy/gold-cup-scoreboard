# Scoreboards

Static tournament scoreboards — one page per tournament, served from a single
GitHub Pages site. A small Ruby build reads each tournament's CSV, renders an
HTML page (standings, fixtures/results, projected bracket), and a landing page
that links to them all. Live tournaments auto-refresh from a public Google Sheet
on a schedule during their date window; finished tournaments are frozen.

Live site: `https://<username>.github.io/<repo>/`
Each tournament: `…/<repo>/<slug>/`

## Layout

```
tournaments/
  <slug>/
    data.csv      # the tournament data (see "CSV format" below)
    meta.yml      # title/location/category, optional live: block, archived: flag
build.rb          # renders every non-archived tournament + the landing page into docs/
fetch.rb          # refreshes live tournaments' CSVs from their sheets (date-gated)
lib/parser.rb     # CSV -> structured data (the format-specific part)
lib/template.html.erb   # a tournament page
lib/landing.html.erb    # the index that links to all tournaments
docs/             # generated + COMMITTED output (Pages serves this)
  index.html              # landing
  <slug>/index.html       # one per tournament
.github/workflows/deploy.yml   # fetch (date-gated) -> build -> deploy on push/schedule/manual
```

`docs/` is committed on purpose: an **archived** tournament is never rebuilt, so
its committed page is what stays live — immune to later parser/template changes.

## Adding a tournament

1. `cp -r tournaments/beaverton-4x4-cup tournaments/<new-slug>`
2. Replace `data.csv` with the new tournament's CSV.
3. Edit `meta.yml`: set `title`, `location`, `category`. For auto-refresh, set
   the `live:` block (`sheet_url` = public CSV export, `start`/`end` = window,
   America/Los_Angeles, inclusive). For a static, hand-committed CSV, delete the
   `live:` block.
4. `ruby build.rb` to render locally, then commit and push. The page appears at
   `…/<repo>/<new-slug>/` and is linked from the landing page.

**Every CSV is different.** If a new tournament's CSV layout differs enough that
standings/games don't parse, that's a `lib/parser.rb` change — the one
format-specific file. Hand me the CSV and I'll adapt it.

## When a tournament ends

Set `archived: true` in its `meta.yml` (and you can drop the `live:` block).
From then on `fetch.rb` never refreshes it and `build.rb` never regenerates it —
the page already in `docs/<slug>/` is frozen and served as-is forever. It still
appears on the landing page (marked **Final**). No code needs to keep supporting
an old CSV's quirks once it's archived.

## Updating scores

- **Live tournament (in window):** nothing to do — GitHub Actions fetches the
  sheet every ~10 min during the window and redeploys. Refresh the page.
- **Force a refresh now:** Actions → *Build and deploy scoreboards* → *Run
  workflow*. Manual runs always fetch + deploy, regardless of date.
- **Static tournament:** replace `tournaments/<slug>/data.csv`, run `ruby
  build.rb`, commit, push.

## Schedule & date-gating

`deploy.yml` runs on push, manual dispatch, and a cron
(`*/10 15-23 * * 6,0`, UTC — ~8 AM–4 PM Pacific, Sat & Sun; no DST adjustment;
GitHub scheduled runs are best-effort). The cron just wakes the job up; what
actually scopes refreshes is each tournament's `live:` window in `fetch.rb`. On
a scheduled run with no open window, `fetch.rb` reports `proceed=false` and the
build/deploy steps are skipped (a clean green no-op).

A manual dispatch always proceeds and fetches every live tournament (forced),
which is the way to test.

## Run it locally

```bash
ruby build.rb                      # all non-archived tournaments + landing -> docs/
ruby build.rb tournaments/<slug>   # just one tournament (offline preview)
ruby build.rb path.csv out.html    # one-off: a bare CSV to a file
open docs/index.html
```

`fetch.rb` is only for CI (it hits the network); `build.rb` works fully offline
from the committed CSVs. Requires Ruby 3.x (standard library only: `csv`, `erb`,
`json`, `yaml`).

## CSV format

The parser expects one tournament per CSV, in the sheet's native shape:

```
,,,,U10 Boys Gold                      <- title row (ignored for the page title; meta.yml drives that)
,,,,,POINTS
,,,,16B WSM Adi Stars,18               <- team, points
... more teams ...
Game#,Day,Time,Field,Home Team,SCORE,POINTS,Away Team,SCORE,POINTS
U10BG1,Saturday 6/13,9:30 AM,3-4,16B WSM Adi Stars,5,9,16B WSM Tiro,4,3
... more games ...
```

It tolerates the common quirks: blank leading columns, doubled spaces in team
names, blank score cells (shown as upcoming), seed placeholders like
`1st in Points`, and trailing round labels (`Final`, `Consolation`).
