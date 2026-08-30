# Snapshots `primary` and nothing else. Of the four production databases only this one holds
# work that cannot be recreated — classes, tests, attempts, grades; cache, queue and cable are
# all rebuildable, and copying them would cost disk for the privilege of restoring stale jobs.
class DatabaseBackup
  RETAINED = 7
  PREFIX = "primary-".freeze

  class << self
    def create!(directory: default_directory)
      new(directory).create!
    end

    def default_directory
      Rails.root.join("storage/backups")
    end
  end

  def initialize(directory)
    @directory = Pathname(directory)
  end

  def create!
    @directory.mkpath
    path = @directory.join(filename)

    # VACUUM INTO, never a file copy. Under WAL the .sqlite3 file on its own is not a database:
    # the newest commits sit in -wal until a checkpoint, so `cp` yields a backup that restores
    # to a moment nobody ever saw. This runs in a read transaction — students mid-answer keep
    # writing — and the file it leaves is consistent as of the instant it started. It also
    # refuses to overwrite, which is why two snapshots in one second raise instead of silently
    # collapsing into one.
    ActiveRecord::Base.with_connection do |connection|
      connection.execute("VACUUM INTO #{connection.quote(path.to_s)}")
    end

    Rails.logger.info("Database backup written: #{path} (#{path.size} bytes)")
    prune!
    path
  end

  private

  # Sorting is what picks the victims, so the stamp is UTC: Kyiv time steps backwards at the end
  # of DST, and one hour a year an older backup would sort as the newest and outlive the rest.
  def filename
    "#{PREFIX}#{Time.current.utc.strftime('%Y%m%dT%H%M%SZ')}.sqlite3"
  end

  # Globbed by our own prefix, so anything else an operator left in the directory stays.
  def prune!
    backups = @directory.glob("#{PREFIX}*.sqlite3").sort
    (backups - backups.last(RETAINED)).each(&:delete)
  end
end
