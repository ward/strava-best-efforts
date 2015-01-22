require 'yaml'
# For options
require 'optparse'
require 'logger'
require './mystrava'

def pretty_print_time seconds
  if seconds < 3600
    return format("%d:%02d", seconds / 60, seconds % 60)
  else
    return format("%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
  end
end

options = OpenStruct.new
options.fetch = false
OptionParser.new do |opts|
  opts.banner = "Usage: main.rb [options]"

  opts.on("-d", "--distance DISTANCE",
          "Distance for which to output your leaderboard.",
          "Choices: 400, 805, 1000, 1609, 3219, 5000",
          "10000, 15000, 16090, 20000, 21097",
          "(and higher if you did those)") do |distance|
    options[:distance] = distance
  end
  opts.on("-f", "--[no-]fetch",
          "Connects to Strava and fetches all run info to save locally") do |v|
    options[:fetch] = v
  end
  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!

config = YAML.load_file('config.yml')
logger = Logger.new(STDOUT)
logger.level = Logger::INFO
strava = MyStrava.new(access_token: config['access_token'], logger: logger)

if options[:fetch]
  strava.fetch()
elsif not options[:distance].nil?
  puts "For distance: " + options[:distance]
  efforts = strava.best_efforts(options[:distance])
  efforts.each.with_index(1) do |row,idx|
    puts format("%3d. %8s     (%s)",
                idx, pretty_print_time(row[0]), Time.at(row[1]).strftime("%F"))
  end
else
  puts "Nothing to do..."
end

