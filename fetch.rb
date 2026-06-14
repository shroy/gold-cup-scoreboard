#!/usr/bin/env ruby
# Refresh live tournament CSVs from their public Google Sheet exports.
#
# For each NON-archived tournament that declares a `live:` block in meta.yml,
# this fetches the sheet CSV and overwrites tournaments/<slug>/data.csv — but
# only when "today" (America/Los_Angeles) falls inside that tournament's
# [start, end] window, unless forced.
#
# Archived tournaments are never touched: their page is frozen.
#
# Env:
#   EVENT_NAME  - GitHub event ("workflow_dispatch" forces a fetch regardless of
#                 date; "schedule" only proceeds if a window is currently open;
#                 anything else, e.g. "push", proceeds and fetches in-window).
#   TZ          - set to America/Los_Angeles by the workflow so Date.today is Pacific.
#
# Writes `proceed=<bool>` and `refreshed=<n>` to $GITHUB_OUTPUT when present, so
# the workflow can decide whether to build + deploy. Exits non-zero only on a
# genuine fetch/validation failure (so we never deploy garbage over a good page).
require "date"
require_relative "lib/tournaments"

HEADER_TOKEN = "Game#".freeze

event   = ENV["EVENT_NAME"].to_s
force   = event == "workflow_dispatch"
today   = Date.today   # respects TZ env (workflow sets America/Los_Angeles)

puts "Event: #{event.empty? ? '(manual)' : event}  Today (#{ENV['TZ'] || 'local'}): #{today}"

live = Tournament::Tournaments.all.select(&:live?)
if live.empty?
  puts "No live tournaments configured — nothing to fetch."
end

in_window = 0
refreshed = 0

live.each do |t|
  start_d = Date.parse(t.live["start"].to_s)
  end_d   = Date.parse(t.live["end"].to_s)
  open    = (start_d..end_d).cover?(today)
  in_window += 1 if open

  unless force || open
    puts "· #{t.slug}: outside window #{start_d}..#{end_d} — skipping."
    next
  end

  url = t.live["sheet_url"]
  puts "· #{t.slug}: fetching#{force && !open ? ' (forced)' : ''} from sheet…"

  # curl -fSL --retry 3 so a flaky network / HTTP error fails rather than
  # leaving a truncated or empty file.
  ok = system("curl", "-fSL", "--retry", "3", url, "-o", t.csv_path)
  abort "::error::#{t.slug}: download failed (curl exit)." unless ok

  body = File.exist?(t.csv_path) ? File.read(t.csv_path) : ""
  if body.strip.empty?
    abort "::error::#{t.slug}: fetched CSV is empty — refusing to build/deploy."
  end
  unless body.include?(HEADER_TOKEN)
    # A restricted sheet returns an HTML login page (no "Game#") — caught here.
    abort "::error::#{t.slug}: fetched data is missing the '#{HEADER_TOKEN}' header " \
          "(restricted sheet?). Refusing to build/deploy."
  end

  puts "  ✓ #{t.slug}: #{body.bytesize} bytes."
  refreshed += 1
end

proceed =
  case event
  when "schedule" then in_window.positive?  # date-gate: idle outside any window
  else true                                 # manual / push always proceed
  end

puts "Summary: refreshed=#{refreshed}, in_window=#{in_window}, proceed=#{proceed}"

if (out = ENV["GITHUB_OUTPUT"])
  File.open(out, "a") do |f|
    f.puts "proceed=#{proceed}"
    f.puts "refreshed=#{refreshed}"
  end
end
