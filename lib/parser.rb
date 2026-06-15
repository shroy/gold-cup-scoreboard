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
      header_idx = @rows.index { |r| r.any? { |c| c.casecmp?(GAMES_HEADER_KEY) } }
      raise "No 'Game#' header row found — is this the right CSV?" unless header_idx

      all_games = games(@rows[(header_idx + 1)..], column_map(@rows[header_idx]))
      {
        division:  division_name(@rows[0...header_idx]),
        teams:     standings(@rows[0...header_idx]),
        games:     all_games,
        placement: placement(all_games),
      }
    end

    private

    # Maps the games-header row to column indexes by LABEL, so the sheet's
    # columns can be reordered without breaking the parser. The two "SCORE"
    # columns are disambiguated as the ones following Home Team / Away Team.
    def column_map(header)
      find = ->(label) { header.index { |c| c.casecmp?(label) } }
      home = find.("Home Team")
      away = find.("Away Team")
      score_after = ->(i) { (i...header.length).find { |j| header[j].casecmp?("SCORE") } if i }
      {
        game:        find.("Game#"),
        day:         find.("Day"),
        time:        find.("Time"),
        field:       find.("Field"),
        home:        home,
        away:        away,
        home_score:  score_after.(home),
        away_score:  score_after.(away),
      }
    end

    # Title is the first non-empty cell of the first non-blank row in the block
    # above the games header (the title may share its row with a "POINTS" label).
    def division_name(block)
      row = block.find { |r| r.any? { |c| !c.empty? } }
      row&.reject(&:empty?)&.first || "Tournament Division"
    end

    # Standings block: rows above the games header. A team row is any row whose
    # last non-empty cell is an integer (its points); the name is the cell
    # before it. This skips the title row, the "POINTS" header, and blanks
    # regardless of how many leading/blank columns the export uses.
    def standings(block)
      block.filter_map do |r|
        cells = r.reject(&:empty?)
        next if cells.length < 2 || !integer?(cells.last)

        { name: normalize_name(cells[-2]), points: cells.last.to_i }
      end
    end

    def games(block, cols)
      block.filter_map do |r|
        no = at(r, cols[:game])
        next if no.empty?

        home = normalize_name(at(r, cols[:home]))
        away = normalize_name(at(r, cols[:away]))
        label = trailing_label(r, cols[:away_score])
        seed = seed_placeholder?(home) || seed_placeholder?(away) || !label.nil?

        {
          id:    no,
          day:   at(r, cols[:day]),
          time:  at(r, cols[:time]),
          field: at(r, cols[:field]),
          # For played bracket games the name carries a "Nth in Points - " seed
          # prefix; strip it for display once we know the real team.
          home: strip_seed_prefix(home),
          home_score: score(at(r, cols[:home_score])),
          away: strip_seed_prefix(away),
          away_score: score(at(r, cols[:away_score])),
          # seed number embedded in the bracket name ("3rd in Points - ..."), or nil
          home_seed: seed_number(home),
          away_seed: seed_number(away),
          label: label,
          seed_game: seed,
        }
      end
    end

    # Final placement from completed bracket games. Each placement game pairs
    # two adjacent seeds (e.g. 1 vs 2, 3 vs 4); the winner takes the higher
    # place (lower number), the loser the lower place. Returns a hash of
    # team name => place (1-based), only for games that have been played with
    # both seed numbers known.
    def placement(games)
      result = {}
      games.each do |g|
        next unless g[:seed_game]
        next if g[:home_seed].nil? || g[:away_seed].nil?
        next if g[:home_score].nil? || g[:away_score].nil?

        hi, lo = [g[:home_seed], g[:away_seed]].minmax
        home_wins = g[:home_score] > g[:away_score]
        winner = home_wins ? g[:home] : g[:away]
        loser  = home_wins ? g[:away] : g[:home]
        result[winner] = hi
        result[loser]  = lo
      end
      result
    end

    def at(row, idx)
      idx && row[idx] ? row[idx] : ""
    end

    # The round label ("Final"/"Consolation") trails after the away-score column.
    def trailing_label(row, away_score_idx)
      start = away_score_idx ? away_score_idx + 1 : 0
      last  = row[start..]&.map(&:strip)&.reject(&:empty?)&.last
      bracket_label(last)
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

    # "3rd in Points - 16B WSM Telstar" -> 3 ; returns nil if no seed prefix.
    def seed_number(name)
      m = name.to_s.match(/\A(\d+)\w*\s+in Points\b/i)
      m && m[1].to_i
    end

    # Played bracket games name the team as "5th in Points - 16B WSM Nemeziz".
    # Strip the seed prefix so the real team shows; leave a bare placeholder
    # ("5th in Points", no team yet) untouched.
    def strip_seed_prefix(name)
      name.sub(/\A\d+\w*\s+in Points\s*-\s*/i, "")
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
