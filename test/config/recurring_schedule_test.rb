require "test_helper"
require "fugit"

# Solid Queue skips a recurring entry it cannot make sense of, and says nothing. The first sign
# of a typo here is a backup that was never taken, or attempts that never expired — both noticed
# only when they are already needed.
class RecurringScheduleTest < ActiveSupport::TestCase
  SCHEDULE = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production").freeze

  test "every production task names a class that exists" do
    SCHEDULE.each do |name, task|
      next unless task.key?("class")

      assert_kind_of Class, task["class"].safe_constantize, "#{name}: #{task['class']} does not exist"
    end
  end

  # The same rule SolidQueue::RecurringTask enforces, not a looser one: it parses with
  # multi: :fail and rejects anything that is not a Fugit::Cron. Fugit reads plenty of strings
  # into other shapes — "evry day at 3:30am" among them — so merely parsing proves nothing.
  test "every production task has a schedule solid queue would accept" do
    SCHEDULE.each do |name, task|
      schedule = task.fetch("schedule")

      assert_instance_of Fugit::Cron, Fugit.parse(schedule, multi: :fail),
        "#{name}: #{schedule.inspect} is not a schedule solid queue can run"
    end
  end

  # Named on its own, because the two checks above pass just as happily on a file this entry was
  # deleted from, and a backup nobody takes is the whole failure this feature exists to prevent.
  test "the nightly database backup is scheduled" do
    assert_equal "BackupDatabaseJob", SCHEDULE.dig("backup_database", "class")
  end
end
