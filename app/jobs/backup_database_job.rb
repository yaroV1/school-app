class BackupDatabaseJob < ApplicationJob
  queue_as :default

  def perform
    DatabaseBackup.create!
  end
end
