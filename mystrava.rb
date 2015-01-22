# They really should've documented this part
require 'strava/api/v3'
require 'sqlite3'
# For parse
require 'time'
require 'logger'

# Monkey patch true and false. SQLite does not have booleans
class FalseClass; def to_i; 0 end end
class TrueClass; def to_i; 1 end end

# Handles things related to Strava.
# Can fetch information from the Strava API to save it locally
# Performs queries on the locally saved data.
class MyStrava
	def initialize(options={})
    raise ArgumentError if options[:access_token].nil?

    @logger = options[:logger] || Logger.new(STDOUT)
    @client = Strava::Api::V3::Client.new(access_token: options[:access_token], logger: @logger)
    @db = SQLite3::Database.new "strava.db"
    create_db_schema(@db)
	end
	
  # Contact Strava and fetch data to save locally
  def fetch
    fetch_and_save_runs(list_all_runs())
  end

  # Returns best efforts for a certain distance ordered from best to worst
  # Each entry is an array [timeinseconds, startdateinseconds]
  def best_efforts(distance)
    return @db.execute("SELECT best_effort.elapsed_time, activity.start_date
                        FROM best_effort
                        JOIN activity
                        ON best_effort.activity_id = activity.id
                        WHERE best_effort.distance = ?
                        ORDER BY best_effort.elapsed_time",
                        distance)
  end

  ##############################################################################

  private

  # Creates the correct schema in the sql database
  # Makes use of the create_tables.sql file
  def create_db_schema db
    sqlinput = File.open('create_tables.sql', 'r') { |f| f.read }
    db.execute_batch(sqlinput)
  end

  # Gets a list of summaries for all the runs. Since we need the best
  # efforts, this will not do.
  def list_all_runs
    page = 1
    runs = []

    begin
      @logger.info("Fetching activities page #{page}...")
      acts = @client.list_athlete_activities(per_page: 100, page: page)
      only_runs = acts.reject { |act| act['type'] != 'Run' }
      runs = runs + only_runs
      page = page + 1
    end until acts.length == 0

    return runs
  end
  
  # Takes as input a JSON run activity as retrieved from a specific API call
  def save_run run
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
      @logger.error(e)
      @logger.error("Error for #{run['id']}")
    end
  end

  # Fetches list of all runs, fetches info for each run, saves information
  # locally.
  def fetch_and_save_runs activities
    @logger.info "#{activities.length} activities found."
    @logger.info "Fetching data for each."

    ids_in_db = @db.execute("SELECT id FROM activity").flatten
    activities.each.with_index(1) do |activity,idx|
      if ids_in_db.include? activity['id']
        @logger.info "[#{idx}/#{activities.length}] Activity #{activity['id']} already in database"
        next
      end

      @logger.info "[#{idx}/#{activities.length}] Fetching activity #{activity['id']}... "
      begin
        save_run(@client.retrieve_an_activity(activity['id']))
        @logger.info "[#{idx}/#{activities.length}] Activity #{activity['id']} handled."
      rescue StandardError => e
        @logger.error e
        @logger.error "FAILED TO HANDLE ACTIVITY #{activity['id']}"
      end
    end
    @logger.info "finished"
  end
end
