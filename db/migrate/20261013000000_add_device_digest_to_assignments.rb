class AddDeviceDigestToAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :assignments, :device_digest, :string
  end
end
