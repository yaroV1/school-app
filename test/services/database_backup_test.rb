require "test_helper"

# VACUUM INTO refuses to run inside a transaction, so this case cannot use the transactional
# fixtures the rest of the suite runs on. Each test works in its own tmpdir, which also keeps
# parallel workers off each other's pruning, and the one test that writes a row cleans it up.
class DatabaseBackupTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup { @directory = Pathname(Dir.mktmpdir("backup-test")) }
  teardown { FileUtils.remove_entry(@directory) if @directory.exist? }

  # The point of a backup is that it restores. Asserting a file appeared would pass for a
  # truncated or torn copy just as happily, so open the snapshot as a database and read the
  # teachers back out of it.
  test "writes a snapshot that opens as a database holding the same rows" do
    path = DatabaseBackup.create!(directory: @directory)

    assert_predicate path, :exist?
    SQLite3::Database.new(path.to_s) do |snapshot|
      assert_equal User.count, snapshot.get_first_value("SELECT COUNT(*) FROM users")
      assert_equal User.order(:id).pluck(:email_address),
        snapshot.execute("SELECT email_address FROM users ORDER BY id").flatten
    end
  end

  # The reason this is VACUUM INTO and not a file copy, pinned. A committed row lands in the -wal
  # file and stays there until a checkpoint, so the .sqlite3 file on its own is missing it: a
  # backup taken with cp would restore a database that has lost the last answers a class wrote.
  # Nothing in a quiet test database makes those two look different, which is why this test makes
  # the database not quiet.
  test "captures a committed row still sitting in the write-ahead log" do
    teacher = User.create!(email_address: "wal@example.com", password: "long-enough-secret")

    path = DatabaseBackup.create!(directory: @directory)

    SQLite3::Database.new(path.to_s) do |snapshot|
      assert_includes snapshot.execute("SELECT email_address FROM users").flatten, "wal@example.com"
    end
  ensure
    teacher&.destroy
  end

  test "keeps the newest backups and deletes the rest" do
    made = (1..DatabaseBackup::RETAINED + 2).map do |minute|
      travel_to(Time.utc(2026, 1, 1, 3, minute)) { DatabaseBackup.create!(directory: @directory) }
    end

    kept = @directory.glob("*.sqlite3").sort
    assert_equal DatabaseBackup::RETAINED, kept.size
    assert_equal made.last(DatabaseBackup::RETAINED).map(&:to_s).sort, kept.map(&:to_s)
  end

  # Pruning globs its own prefix, so a snapshot an operator copied in by hand, or anything else
  # sharing the directory, is not swept up by a routine backup.
  test "leaves files it did not write alone" do
    stranger = @directory.join("keep-me.sqlite3")
    stranger.write("not a backup")

    (DatabaseBackup::RETAINED + 1).times do |minute|
      travel_to(Time.utc(2026, 1, 1, 3, minute)) { DatabaseBackup.create!(directory: @directory) }
    end

    assert_predicate stranger, :exist?
  end

  test "creates the backup directory when it is missing" do
    nested = @directory.join("does/not/exist/yet")

    path = DatabaseBackup.create!(directory: nested)

    assert_predicate path, :exist?
  end

  # UTC, not Kyiv: local time steps backwards at the end of DST, and for that one hour a year an
  # older snapshot would sort as the newest and outlive every other.
  test "names snapshots in UTC so they sort in the order they were taken" do
    earlier = travel_to(Time.utc(2026, 10, 25, 0, 30)) { DatabaseBackup.create!(directory: @directory) }
    later = travel_to(Time.utc(2026, 10, 25, 1, 30)) { DatabaseBackup.create!(directory: @directory) }

    assert earlier.basename.to_s < later.basename.to_s
  end
end
