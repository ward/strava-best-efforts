# They really should've documented this part
require 'strava/api/v3'
require 'yaml'
require 'sqlite3'
# For parse
require 'time'
# For options
require 'optparse'

# Gets a list of summaries for all the runs. Since we need the best
# efforts, this will not do.
def get_all_runs
  page = 1
  runs = []

  begin
    acts = @client.list_athlete_activities(per_page: 50, page: page)
    only_runs = acts.reject { |act| act['type'] != 'Run' }
    runs = runs + only_runs
    page = page + 1
  end until acts.length == 0

  return runs
end

# Monkey patch true and false. SQLite does not have booleans
class FalseClass; def to_i; 0 end end
class TrueClass; def to_i; 1 end end


# Takes as input a JSON run activity as retrieved from a specific API call
def run_to_sql run
  # First build hash of what we will put in the db
  keyval = {}

  keyval['id'] = run['id']
  keyval['resource_state'] = run['resource_state']
  keyval['external_id'] = run['external_id']
  keyval['athlete_id'] = run['athlete']['id']
  keyval['name'] = run['name']
  keyval['description'] = run['description']
  keyval['distance'] = run['distance']
  keyval['moving_time'] = run['moving_time']
  keyval['elapsed_time'] = run['elapsed_time']
  keyval['total_elevation_gain'] = run['total_elevation_gain']
  keyval['type'] = run['type']
  keyval['start_date'] = Time.parse(run['start_date']).to_i
  keyval['trainer'] = run['trainer'].to_i
  keyval['commute'] = run['commute'].to_i
  keyval['manual'] = run['manual'].to_i
  keyval['private'] = run['private'].to_i
  keyval['flagged'] = run['flagged'].to_i

  begin
    # TODO: Can we assume .keys and .values will always return in same order?
    @db.execute("INSERT INTO activity (#{keyval.keys.join(', ')})
              VALUES (#{('?,' * keyval.length)[0..-2]})",
              keyval.values)

    # Now the best efforts
    run['best_efforts'].each do |effort|
      @db.execute("INSERT INTO best_effort (distance, moving_time, elapsed_time, activity_id)
                VALUES (?,?,?,?)",
                [effort['distance'],
                 effort['moving_time'],
                 effort['elapsed_time'],
                 effort['activity']['id']])
    end
  rescue SQLite3::ConstraintException => e
    puts e
    puts "Error for #{run['id']}"
  end
end

# Fetches list of all runs, fetches info for each run, saves information
# locally.
def save_all_runs
  activities = get_all_runs()

  puts "#{activities.length} activities"
  activities.each do |activity|
    puts "Activity #{activity['id']}... "
    begin
      run_to_sql(@client.retrieve_an_activity(activity['id']))
      puts "handled."
    rescue Exception => e
      puts e
      puts "FAILED TO HANDLE ACTIVITY #{activity['id']}"
    end
  end
  puts "finished"
end

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
          "Choices: 400, 805, 1000, 1609, 3219, 5000, 10000.",
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
@client = Strava::Api::V3::Client.new(access_token: config['access_token'])
@db = SQLite3::Database.new "strava.db"

if options[:fetch]
  save_all_runs
elsif not options[:distance].nil?
  puts "For distance: " + options[:distance]
  ctr = 1
  @db.execute("SELECT best_effort.elapsed_time, activity.start_date
              FROM best_effort
              JOIN activity
              ON best_effort.activity_id = activity.id
              WHERE best_effort.distance = ?
              ORDER BY best_effort.elapsed_time",
              options[:distance]) do |row|
    puts format("%3d. %8s     (%s)",
                ctr, pretty_print_time(row[0]), Time.at(row[1]).strftime("%F"))
    ctr = ctr + 1
  end
else
  puts "Nothing to do..."
end

