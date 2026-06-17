module Api
  class ScoresController < ApplicationController
    CACHE_KEY = FootballDataPoller::CACHE_KEY

    FALLBACK = {
      "state"      => "upcoming",
      "live"       => [],
      "recent"     => [],
      "upcoming"   => [],
      "updated_at" => nil
    }.freeze

    def index
      raw = Rails.cache.read(CACHE_KEY)
      payload = raw ? JSON.parse(raw) : FALLBACK
      render json: payload
    end
  end
end
