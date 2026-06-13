# 10 Gold Cup — Scoreboard

A static tournament scoreboard. A small Ruby script reads a CSV exported from
the tournament sheet, renders a single HTML page (standings, fixtures/results,
and a projected placement bracket), and GitHub Pages serves it at one permanent
URL. Update by committing a new CSV — the URL never changes.

## One-time setup

1. **Create a repo** on GitHub (public is simplest for free Pages) and push
   these files to the `main` branch.
2. **Enable Pages**: repo → *Settings* → *Pages* → under *Build and deployment*,
   set **Source = GitHub Actions**.
3. That's it. The first push runs the workflow and publishes the page. The live
   URL appears in *Settings → Pages* and in the *Actions* run summary, and looks
   like `https://<your-username>.github.io/<repo-name>/`.

Share that URL. It stays the same for the whole tournament.

## Updating scores (the recurring task)

1. Export/download the latest division data as a CSV (same shape as
   `data/u10-boys-gold.csv`).
2. Replace the file in `data/` with the new one (keep the filename, or pass a
   new one — see below).
3. Commit and push. GitHub Actions rebuilds and redeploys automatically in
   ~1 minute. Refresh the page.

No new links, ever. Anyone holding the URL sees the latest version on refresh.

## Run it locally (optional)

```bash
ruby build.rb                       # uses the first CSV in data/, writes docs/index.html
ruby build.rb data/u10-boys-gold.csv docs/index.html   # explicit paths
open docs/index.html                # preview
```

Requires Ruby 3.x (uses only the standard library — `csv`, `erb`, `json`).

## CSV format

The parser expects one division per CSV, in the sheet's native shape:

```
,,,,U10 Boys Gold                      <- division title
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

**If a future tournament's CSV is shaped differently**, the parser in
`lib/parser.rb` is the one place to adjust — the template and workflow stay the
same.

## Files

```
build.rb                     # entry point: parse CSV -> render HTML
lib/parser.rb                # CSV -> structured data (the format-specific part)
lib/template.html.erb        # the page design
data/*.csv                   # tournament data (commit new ones to update)
docs/index.html              # generated output (served by Pages)
.github/workflows/deploy.yml # build + deploy on every push
```
