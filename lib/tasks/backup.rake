# Recurring backups run from config/recurring.yml. This is the one to reach for by hand before
# something risky — a migration, a bulk import — and the way to check the schedule's plumbing
# actually works without waiting for 3:30am:
#   bin/kamal app exec --reuse "bin/rails db:backup"
namespace :db do
  desc "Write a consistent snapshot of the primary database into storage/backups"
  task backup: :environment do
    path = DatabaseBackup.create!
    $stdout.puts I18n.t("tasks.db_backup.created", path: path, kilobytes: (path.size / 1024.0).round)
  end
end
