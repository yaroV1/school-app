require "test_helper"

class SeedsGuardTest < ActiveSupport::TestCase
  # Two doors lead to db/seeds.rb on a server, and neither one covers the other.
  # bin/docker-entrypoint runs db:prepare on every boot; prepare_all seeds a freshly
  # created database whenever its config answers seeds?.
  test "no production database seeds on db:prepare" do
    configs = ActiveRecord::Base.configurations.configs_for(env_name: "production")

    assert_predicate configs, :any?
    configs.each do |config|
      assert_not config.seeds?, "production #{config.name} would seed on db:prepare"
    end
  end

  # db:seed calls load_seed directly and never consults seeds?, so the flag above cannot
  # stop a hand-typed `bin/rails db:seed` on the server. The file's own guard has to —
  # and before the first write, or the demo teacher exists whatever happens next.
  test "loading the seed file in production aborts before it writes" do
    users_before = User.count

    replacing(Rails, :env, -> { ActiveSupport::StringInquirer.new("production") }) do
      capture_io do
        assert_raises(SystemExit) { load Rails.root.join("db/seeds.rb").to_s }
      end
    end

    assert_equal users_before, User.count
  end
end
