require "csv"

# Parses one division's CSV in the "10 Gold Cup" sheet shape.
#
# The format (per division tab) looks like:
#   ,,,,U10 Boys Gold                          <- title row (col index 4)
#   ,,,,,POINTS                                <- header for standings block
#   ,,,,16B WSM Adi Stars,18                   <- team, points  (cols 4,5)
#   ... more team rows ...
#   Game#,Day,Time,Field,Home Team,SCORE,POINTS,Away Team,SCORE,POINTS   <- games header
#   U10BG1,Saturday 6/13,9:30 AM,3-4,Home,5,9,Away,4,3                   <- game rows
#
# Bracket rows use seed placeholders ("1st in Points") and a trailing
# label ("Final" / "Consolation") in the away-points column area.
#
# The parser is intentionally defensive: blank leading columns, doubled
# spaces in team names, and missing score cells are all normalized.
module Tournament
  class Parser
    GAMES_HEADER_KEY = "Game#".freeze

    def self.parse(path)
      rows = CSV.read(path)
      new(rows).parse
    end

    def initialize(rows)
      @rows = rows.map { |r| r.map { |c| clean(c) } }
    end

    def parse
      header_idx = @rows.index { |r| r.compact.first == GAMES_HEADER_KEY }
      raise "No 'Game#' header row found — is this the right CSV?" unless header_idx

      {
        division: division_name,
        teams:    standings(@rows[0...header_idx]),
        games:    games(@rows[(header_idx + 1)..]),
      }
    end

    private

    # Title sits in the first non-empty cell of row 0 (after blank cols).
    def division_name
      first = @rows[0]&.compact&.reject(&:empty?)&.first
      first || "Tournament Division"
    end

    # Standings block: rows before the games header that have a team name
    # and a numeric (or blank) points value. We detect "team rows" as those
    # whose last two non-empty cells look like [name, number].
    def standings(block)
      teams = []
      block.each do |r|
        cells = r.reject(&:empty?)
        next if cells.empty?
        next if cells.first.casecmp?("POINTS")          # skip the POINTS header
        next if looks_like_title?(cells)                 # skip division title

        name, pts = team_and_points(cells)
        next unless name
        teams << { name: name, points: pts }
      end
      teams
    end

    def looks_like_title?(cells)
      cells.length == 1
    end

    # A team row is "<name>, <points>" or just "<name>" (points TBD/blank).
    def team_and_points(cells)
      if cells.length >= 2 && integer?(cells.last)
        [normalize_name(cells[-2]), cells.last.to_i]
      elsif cells.length == 1
        [normalize_name(cells[0]), nil]
      else
        # name spread across cells, no trailing number
        [normalize_name(cells.last), nil]
      end
    end

    def games(block)
      block.filter_map do |r|
        next if r.compact.reject(&:empty?).empty?
        no    = r[0]
        next if no.nil? || no.empty?

        day   = r[1]
        time  = r[2]
        field = r[3]
        home  = normalize_name(r[4])
        hs    = r[5]
        away  = normalize_name(r[7])
        as    = r[8]
        # the round label ("Final"/"Consolation") trails after away-points
        label = r[9..]&.compact&.map(&:strip)&.reject(&:empty?)&.last

        {
          id:    no,
          day:   day,
          time:  time,
          field: field,
          home:  home,
          home_score: score(hs),
          away:  away,
          away_score: score(as),
          label: bracket_label(label),
          seed_game: seed_placeholder?(home) || seed_placeholder?(away),
        }
      end
    end

    def bracket_label(label)
      return nil if label.nil?
      case label.downcase
      when "final"       then "Final"
      when "consolation" then "Consolation"
      else nil
      end
    end

    def seed_placeholder?(name)
      name.to_s.match?(/\bin Points\b/i)
    end

    def score(v)
      return nil if v.nil? || v.strip.empty?
      integer?(v) ? v.to_i : nil
    end

    def integer?(v)
      v.to_s.strip.match?(/\A-?\d+\z/)
    end

    # Collapse doubled spaces; trim.
    def normalize_name(v)
      v.to_s.gsub(/\s+/, " ").strip
    end

    def clean(c)
      c.nil? ? "" : c.to_s.strip
    end
  end
end
