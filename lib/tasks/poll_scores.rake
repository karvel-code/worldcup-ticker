namespace :poll do
  desc "Fetch latest World Cup scores from football-data.org and write to cache"
  task scores: :environment do
    result = EspnPoller.call
    puts "live=#{result[:live].size} recent=#{result[:recent].size} upcoming=#{result[:upcoming].size}"
  end
end
