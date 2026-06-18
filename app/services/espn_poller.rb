require "faraday"
require "json"
require "date"

class EspnPoller
  ESPN_BASE = "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard"
  CACHE_KEY = "worldcup_scores"
  CACHE_TTL = 5.minutes

  def self.call = new.call

  def call
    live     = []
    recent   = []
    upcoming = []
    cutoff   = Time.now.utc - 24.hours
    now      = Time.now.utc

    [-1, 0, 1].each do |offset|
      date_str = (Date.today + offset).strftime("%Y%m%d")
      fetch_events(date_str).each do |event|
        match      = parse_event(event)
        next unless match
        state      = event.dig("status", "type", "state")
        match_time = parse_time(event["date"])

        case state
        when "in"   then live << match
        when "post" then recent   << match if match_time && match_time >= cutoff
        when "pre"  then upcoming << match if match_time && match_time >= now
        end
      end
    end

    recent   = recent.sort_by   { |m| m[:utc_date] }.reverse.first(8)
    upcoming = upcoming.sort_by { |m| m[:utc_date] }.first(6)

    payload = { live: live, recent: recent, upcoming: upcoming }
    Rails.cache.write(CACHE_KEY, payload.to_json, expires_in: CACHE_TTL)
    Rails.logger.info "[EspnPoller] live=#{live.size} recent=#{recent.size} upcoming=#{upcoming.size}"
    payload
  rescue => e
    Rails.logger.error "[EspnPoller] #{e.class}: #{e.message}"
    nil
  end

  private

  def fetch_events(date_str)
    url  = "#{ESPN_BASE}?dates=#{date_str}&limit=100"
    resp = Faraday.get(url) do |req|
      req.headers["User-Agent"] = "Mozilla/5.0 WorldCupTicker/1.0"
      req.options.timeout = 12
    end
    return [] unless resp.success?
    JSON.parse(resp.body).fetch("events", [])
  rescue => e
    Rails.logger.warn "[EspnPoller] fetch #{date_str}: #{e.message}"
    []
  end

  def parse_event(event)
    comp = event.dig("competitions", 0)
    return nil unless comp

    competitors = comp["competitors"] || []
    home = competitors.find { |c| c["homeAway"] == "home" }
    away = competitors.find { |c| c["homeAway"] == "away" }
    return nil unless home && away

    status_name = event.dig("status", "type", "name").to_s
    is_halftime = status_name == "STATUS_HALFTIME"
    is_live     = event.dig("status", "type", "state") == "in"

    minute = nil
    if is_live && !is_halftime
      clock  = event.dig("status", "displayClock").to_s
      parsed = clock.split(":").first.to_i
      minute = parsed if parsed > 0
    end

    {
      home:        home.dig("team", "displayName").to_s,
      home_abbrev: home.dig("team", "abbreviation").to_s,
      away:        away.dig("team", "displayName").to_s,
      away_abbrev: away.dig("team", "abbreviation").to_s,
      home_score:  home["score"].to_i,
      away_score:  away["score"].to_i,
      status:      is_halftime ? "PAUSED" : (is_live ? "IN_PLAY" : status_name),
      minute:      minute,
      group:       parse_group(comp),
      venue_city:  parse_venue_city(comp["venue"]),
      utc_date:    event["date"].to_s,
    }
  end

  def parse_group(comp)
    # altGameNote e.g. "FIFA World Cup, Group A"
    alt = comp["altGameNote"].to_s
    m   = alt.match(/Group\s+\w+/i)
    return m[0] if m

    # Fallback: check notes array
    note = (comp["notes"] || []).find { |n| n["headline"].to_s.match?(/group/i) }
    note ? note["headline"] : nil
  end

  def parse_venue_city(venue)
    return nil unless venue
    city  = venue.dig("address", "city").to_s.strip
    state = venue.dig("address", "state").to_s.strip
    parts = [city, state].reject(&:empty?)
    parts.empty? ? venue["fullName"].to_s : parts.join(", ")
  end

  def parse_time(str)
    Time.parse(str.to_s)
  rescue
    nil
  end
end
