require "faraday"

class FootballDataPoller
  BASE_URL = "https://api.football-data.org/v4"
  COMPETITION = "WC"
  CACHE_KEY = "worldcup_scores"
  RECENT_HOURS = 24

  def self.call
    new.call
  end

  def call
    live    = fetch_live
    other   = fetch_date_range
    recent  = filter_recent(other)
    upcoming = filter_upcoming(other)

    state = if live.any?      then "live"
            elsif recent.any? then "recent"
            else                   "upcoming"
            end

    payload = {
      state:      state,
      live:       live,
      recent:     recent,
      upcoming:   upcoming,
      updated_at: Time.current.iso8601
    }

    Rails.cache.write(CACHE_KEY, payload.to_json, expires_in: 5.minutes)
    Rails.logger.info "[FootballDataPoller] state=#{state} live=#{live.size} recent=#{recent.size} upcoming=#{upcoming.size}"
    payload
  end

  private

  def fetch_live
    response = conn.get("competitions/#{COMPETITION}/matches") do |req|
      req.params["status"] = "IN_PLAY,PAUSED"
    end
    parse_matches(response.body["matches"] || [])
  rescue => e
    Rails.logger.error "[FootballDataPoller] fetch_live failed: #{e.message}"
    []
  end

  def fetch_date_range
    yesterday = (Date.current - 1).iso8601
    tomorrow  = (Date.current + 1).iso8601
    response = conn.get("competitions/#{COMPETITION}/matches") do |req|
      req.params["dateFrom"] = yesterday
      req.params["dateTo"]   = tomorrow
    end
    response.body["matches"] || []
  rescue => e
    Rails.logger.error "[FootballDataPoller] fetch_date_range failed: #{e.message}"
    []
  end

  def filter_recent(matches)
    cutoff = Time.current - RECENT_HOURS.hours
    matches
      .select { |m| m["status"] == "FINISHED" }
      .select { |m| Time.parse(m["utcDate"]) >= cutoff }
      .sort_by { |m| m["utcDate"] }.reverse
      .first(8)
      .map { |m| normalise(m) }
  end

  def filter_upcoming(matches)
    matches
      .select { |m| %w[SCHEDULED TIMED].include?(m["status"]) }
      .select { |m| Time.parse(m["utcDate"]) > Time.current }
      .sort_by { |m| m["utcDate"] }
      .first(6)
      .map { |m| normalise(m) }
  end

  def parse_matches(matches)
    matches.map { |m| normalise(m) }
  end

  def normalise(match)
    {
      home:       match.dig("homeTeam", "shortName") || match.dig("homeTeam", "name"),
      away:       match.dig("awayTeam", "shortName") || match.dig("awayTeam", "name"),
      home_score: match.dig("score", "fullTime", "home"),
      away_score: match.dig("score", "fullTime", "away"),
      minute:     match["minute"],
      status:     match["status"],
      utc_date:   match["utcDate"],
      group:      format_group(match["group"])
    }
  end

  def format_group(raw)
    return nil if raw.nil?
    # API returns "GROUP_A" or "Group A" — normalise to "Group A"
    raw.to_s.sub(/\AGROUP_/i, "Group ")
  end

  def conn
    @conn ||= Faraday.new(BASE_URL) do |f|
      f.headers["X-Auth-Token"] = ENV.fetch("FOOTBALL_DATA_API_TOKEN", "")
      f.response :json
    end
  end
end
