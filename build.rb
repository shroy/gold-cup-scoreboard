#!/usr/bin/env ruby
# Usage: ruby build.rb [data/file.csv] [output.html]
# Defaults: first CSV in data/, written to docs/index.html (GitHub Pages source).

require "erb"
require "json"
require "time"
require_relative "lib/parser"

class Generator
  TEMPLATE = File.join(__dir__, "lib", "template.html.erb")

  def initialize(csv_path)
    @data = Tournament::Parser.parse(csv_path)
  end

  def render
    src = File.read(TEMPLATE, encoding: "UTF-8")
    erb = ERB.new(src, trim_mode: "-")
    erb.filename = TEMPLATE
    # ensure the generated Ruby is treated as UTF-8 (emoji in template)
    eval("# encoding: UTF-8\n" + erb.src, binding, TEMPLATE) # rubocop:disable Security/Eval
  end

  private

  attr_reader :data

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
  def games_json
    JSON.generate(data[:games])
  end

  def ranked_json
    JSON.generate(ranked)
  end

  def days_json
    JSON.generate(days)
  end
end

csv = ARGV[0] || Dir[File.join(__dir__, "data", "*.csv")].sort.first
abort "No CSV found in data/. Pass one as the first argument." unless csv && File.exist?(csv)

out = ARGV[1] || File.join(__dir__, "docs", "index.html")
require "fileutils"
FileUtils.mkdir_p(File.dirname(out))

html = Generator.new(csv).render
File.write(out, html)
puts "Built #{out} from #{File.basename(csv)} (#{html.bytesize} bytes)"
