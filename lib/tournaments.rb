require "yaml"

# Discovers tournaments under tournaments/<slug>/ and exposes their config.
#
# Each tournament is a directory containing:
#   data.csv   - the tournament data (see lib/parser.rb for the expected shape)
#   meta.yml   - title/location/category, optional `live:` block, `archived:` flag
#
# A tournament is "live" (eligible for scheduled auto-fetch) when meta has a
# `live:` block AND is not archived. A tournament is "buildable" (eligible for
# rebuild) when it is not archived — archived pages are frozen as already
# committed in docs/<slug>/.
module Tournament
  Entry = Struct.new(:slug, :dir, :meta, keyword_init: true) do
    def csv_path = File.join(dir, "data.csv")
    def title    = meta["title"] || slug
    def location = meta["location"]
    def category = meta["category"] || "Soccer · Round Robin"
    def archived? = meta["archived"] == true
    def live      = meta["live"]            # nil or {"sheet_url"=>, "start"=>, "end"=>}
    def live?     = !archived? && live.is_a?(Hash) && live["sheet_url"]
    def buildable? = !archived?
  end

  module Tournaments
    ROOT = File.expand_path("../tournaments", __dir__)

    # All tournaments, sorted by slug, regardless of state.
    def self.all
      Dir.glob(File.join(ROOT, "*", "meta.yml")).sort.map do |meta_path|
        dir  = File.dirname(meta_path)
        meta = YAML.safe_load_file(meta_path) || {}
        Entry.new(slug: File.basename(dir), dir: dir, meta: meta)
      end
    end

    def self.find(slug)
      all.find { |t| t.slug == slug }
    end
  end
end
