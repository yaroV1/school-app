require "test_helper"
require "rake"

class TeacherCreateTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    @task = Rake::Task["teacher:create"]
    @task.reenable
  end

  test "creates a teacher from the prompted email and password" do
    assert_difference -> { User.count }, 1 do
      run_task("new-teacher@example.com\nlong-enough-secret\nlong-enough-secret\n")
    end

    teacher = User.find_by(email_address: "new-teacher@example.com")
    assert teacher.authenticate("long-enough-secret")
    assert_includes @output,
      I18n.t("tasks.teacher_create.created", email: teacher.email_address, id: teacher.id)
  end

  # I18n.t answers a missing key with a "Translation missing" string rather than raising, so a
  # typo in any key this task prints would otherwise reach the one person who cannot debug it.
  test "prints no missing translations on any path" do
    run_task("new-teacher@example.com\nlong-enough-secret\nlong-enough-secret\n")
    assert_not_includes @output.downcase, "translation missing"

    @task.reenable
    assert_raises(SystemExit) { run_task("short-pw@example.com\nshort\nshort\n") }
    assert_not_includes @output.downcase, "translation missing"

    @task.reenable
    assert_raises(SystemExit) { run_task("typo@example.com\nlong-enough-secret\nlong-enough-secretz\n") }
    assert_not_includes @output.downcase, "translation missing"
  end

  test "normalizes the email the same way the model does" do
    run_task("  MiXeD@Example.COM \nlong-enough-secret\nlong-enough-secret\n")

    assert_equal "mixed@example.com", User.last.email_address
  end

  test "refuses a password under the minimum length" do
    assert_no_difference -> { User.count } do
      assert_raises(SystemExit) { run_task("short-pw@example.com\nshort\nshort\n") }
    end

    # The floor is User's now, so the task must be repeating the model's sentence, not its own.
    assert_includes @output, I18n.t("errors.messages.too_short", count: User::MINIMUM_PASSWORD_LENGTH)
  end

  # The confirmation is read after the length check, so a typo in an otherwise long enough
  # password is caught by its own guard rather than falling through to User#save.
  test "refuses a password that does not match its confirmation" do
    assert_no_difference -> { User.count } do
      assert_raises(SystemExit) { run_task("typo@example.com\nlong-enough-secret\nlong-enough-secretz\n") }
    end

    assert_includes @output, I18n.t("auth.passwords.mismatch")
  end

  test "refuses a blank email" do
    assert_no_difference -> { User.count } do
      assert_raises(SystemExit) { run_task("\nlong-enough-secret\nlong-enough-secret\n") }
    end
  end

  # Uniqueness is the model's, and its normalization means a teacher cannot be duplicated by
  # retyping the same address in a different case.
  test "refuses an email that already belongs to a teacher" do
    taken = users(:one).email_address.upcase

    assert_no_difference -> { User.count } do
      assert_raises(SystemExit) { run_task("#{taken}\nlong-enough-secret\nlong-enough-secret\n") }
    end
  end

  private
    # The task reads $stdin and writes $stdout directly so it can drop terminal echo. Swap all
    # three streams, and keep what it printed even when abort unwinds the invoke.
    def run_task(input)
      original = [ $stdin, $stdout, $stderr ]
      $stdin = StringIO.new(input)
      $stdout = StringIO.new
      $stderr = StringIO.new
      begin
        @task.invoke
      ensure
        @output = $stdout.string + $stderr.string
        $stdin, $stdout, $stderr = original
      end
      @output
    end
end
