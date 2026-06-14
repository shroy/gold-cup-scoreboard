#!/usr/bin/env ruby
# Build the scoreboard site.
#
#   ruby build.rb                      # build every non-archived tournament +
#                                      # the landing page into docs/
#   ruby build.rb tournaments/<slug>   # build just one tournament (offline preview)
#   ruby build.rb path.csv out.html    # one-off: render a bare CSV to a file
#
# Archived tournaments are skipped — their docs/<slug>/index.html is frozen.
require "erb"
require "json"
require "time"
require "fileutils"
require_relative "lib/parser"
require_relative "lib/tournaments"

DOCS = File.join(__dir__, "docs")

# Renders one tournament page from a parsed-data hash + a meta-ish object that
# answers title/location/category.
class Generator
  TEMPLATE = File.join(__dir__, "lib", "template.html.erb")

  def initialize(data, meta)
    @data = data
    @meta = meta
  end

  def render
    src = File.read(TEMPLATE, encoding: "UTF-8")
    erb = ERB.new(src, trim_mode: "-")
    erb.filename = TEMPLATE
    # ensure the generated Ruby is treated as UTF-8 (emoji in template)
    eval("# encoding: UTF-8\n" + erb.src, binding, TEMPLATE) # rubocop:disable Security/Eval
  end

  private

  attr_reader :data, :meta

  # --- branding (from meta) ---
  def title    = meta.title
  def location = meta.location
  def category = meta.category
  def division = data[:division]              # from the CSV title row
  def logo     = meta.respond_to?(:logo?) && meta.logo? ? meta.logo_file : nil

  def ranked
    @ranked ||= data[:teams].sort_by { |t| -(t[:points] || -1) }
  end

  def days
    @days ||= data[:games].map { |g| g[:day] }.compact.uniq
  end

  def generated_at
    Time.now.strftime("%a %b %-d · %-l:%M %p")
  end

  # --- helpers used by the ERB (server-rendered standings) ---
  def short_name(n)
    n.to_s.sub(/^\d+B?\s+/, "").sub(/^WSM\s+/, "")
  end

  def initials(n)
    short_name(n).sub(/^TS\s+/, "")[0, 2].to_s.upcase
  end

  def short_day(d)
    d.to_s.split.first # "Saturday 6/13" -> "Saturday"
  end

  def day_key(d)
    d.to_s.downcase.gsub(/[^a-z0-9]+/, "-")
  end

  # --- JSON blobs handed to the client script ---
  def games_json  = JSON.generate(data[:games])
  def ranked_json = JSON.generate(ranked)
  def days_json   = JSON.generate(days)
end

# Renders the landing page that links to every tournament.
class LandingGenerator
  TEMPLATE = File.join(__dir__, "lib", "landing.html.erb")

  def initialize(entries)
    @entries = entries
  end

  def render
    src = File.read(TEMPLATE, encoding: "UTF-8")
    erb = ERB.new(src, trim_mode: "-")
    erb.filename = TEMPLATE
    eval("# encoding: UTF-8\n" + erb.src, binding, TEMPLATE) # rubocop:disable Security/Eval
  end

  private

  attr_reader :entries

  def generated_at = Time.now.strftime("%a %b %-d · %-l:%M %p")
end

# Minimal meta shim for the bare-CSV mode (no meta.yml).
BareMeta = Struct.new(:title, :location, :category)

def build_tournament(entry)
  data = Tournament::Parser.parse(entry.csv_path)
  html = Generator.new(data, entry).render
  dir  = File.join(DOCS, entry.slug)
  FileUtils.mkdir_p(dir)
  File.write(File.join(dir, "index.html"), html)
  FileUtils.cp(entry.logo_path, File.join(dir, entry.logo_file)) if entry.logo?
  puts "Built #{File.join(dir, 'index.html')} (#{html.bytesize} bytes) — #{entry.title}"
  data
end

# --- entry point -------------------------------------------------------------
arg = ARGV[0]

if arg && arg.end_with?(".csv")
  # one-off bare CSV -> file
  out = ARGV[1] || File.join(DOCS, "index.html")
  FileUtils.mkdir_p(File.dirname(out))
  data = Tournament::Parser.parse(arg)
  meta = BareMeta.new("Tournament", nil, "Soccer · Round Robin")
  File.write(out, Generator.new(data, meta).render)
  puts "Built #{out} from #{File.basename(arg)}"
elsif arg
  # single tournament by path or slug (offline preview)
  entry = Tournament::Tournaments.find(File.basename(arg)) ||
          abort("No tournament '#{arg}' under tournaments/.")
  abort "Tournament '#{entry.slug}' is archived (frozen) — not rebuilding." if entry.archived?
  build_tournament(entry)
else
  # full site: every buildable tournament + landing page
  entries = Tournament::Tournaments.all
  buildable = entries.select(&:buildable?)
  abort "No tournaments found under tournaments/." if entries.empty?

  buildable.each { |e| build_tournament(e) }
  skipped = entries.reject(&:buildable?)
  skipped.each { |e| puts "Skipped #{e.slug} (archived — page frozen)." }

  # Landing page lists ALL tournaments (archived ones still link to their page).
  FileUtils.mkdir_p(DOCS)
  landing = LandingGenerator.new(entries).render
  File.write(File.join(DOCS, "index.html"), landing)
  puts "Built #{File.join(DOCS, 'index.html')} (landing, #{entries.size} tournaments)"
end
