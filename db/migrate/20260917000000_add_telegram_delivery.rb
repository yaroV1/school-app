class AddTelegramDelivery < ActiveRecord::Migration[8.1]
  def change
    add_column :students, :telegram_username, :string
    add_column :students, :telegram_chat_id, :bigint
    add_column :students, :telegram_pending_chat_id, :bigint
    add_column :students, :telegram_pending_name, :string
    add_index :students, [ :teacher_id, :telegram_username ], unique: true
    add_index :students, [ :teacher_id, :telegram_chat_id ], unique: true

    add_column :class_groups, :telegram_join_token, :string
    reversible do |direction|
      direction.up do
        select_values("SELECT id FROM class_groups").each do |id|
          execute "UPDATE class_groups SET telegram_join_token = #{quote(SecureRandom.urlsafe_base64(24))} WHERE id = #{quote(id)}"
        end
      end
    end
    change_column_null :class_groups, :telegram_join_token, false
    add_index :class_groups, :telegram_join_token, unique: true

    add_column :assignments, :telegram_status, :string, null: false, default: "unsent"
    add_column :assignments, :telegram_request_id, :string
    add_column :assignments, :telegram_chat_id, :bigint
    add_column :assignments, :telegram_token_digest, :string
    add_column :assignments, :telegram_requested_at, :datetime
    add_column :assignments, :telegram_sent_at, :datetime
    add_column :assignments, :telegram_error, :string
  end
end
