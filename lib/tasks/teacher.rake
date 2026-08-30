# The only way to mint a teacher account: there is no registration route, and password reset
# needs a mail server production.rb does not configure yet. On a deployed server run it as
#   bin/kamal app exec --interactive --reuse "bin/rails teacher:create"
# where --interactive is what gives the process a TTY — and the TTY is what keeps the password
# out of the command line, the process list, and shell history, the way ENV would not.
namespace :teacher do
  desc "Create a teacher account, prompting for the email and password"
  task create: :environment do
    minimum_length = 12

    ask = ->(prompt) do
      $stdout.print(prompt)
      $stdout.flush
      $stdin.gets.to_s.strip
    end

    # noecho needs a real terminal. A piped or redirected stdin reads normally so the task still
    # works from a provisioning script, at the cost of whatever echoed the password into it.
    ask_secret = ->(prompt) do
      $stdout.print(prompt)
      $stdout.flush
      secret =
        if $stdin.tty?
          require "io/console"
          $stdin.noecho(&:gets).tap { $stdout.puts }
        else
          $stdin.gets
        end
      secret.to_s.chomp
    end

    email = ask.call(I18n.t("tasks.teacher_create.email"))

    password = ask_secret.call(I18n.t("tasks.teacher_create.password", minimum: minimum_length))
    abort I18n.t("tasks.teacher_create.too_short", minimum: minimum_length) if password.length < minimum_length
    # The reset form states this one already, and it is the same sentence about the same mistake.
    abort I18n.t("auth.passwords.mismatch") if password != ask_secret.call(I18n.t("tasks.teacher_create.repeat"))

    # Presence and uniqueness of the address are the model's, and it phrases those refusals in
    # the same language as the prompts; only the two rules it does not carry — a length floor
    # and a confirmation — are guarded above.
    teacher = User.new(email_address: email, password: password)
    abort teacher.errors.full_messages.to_sentence unless teacher.save

    $stdout.puts I18n.t("tasks.teacher_create.created", email: teacher.email_address, id: teacher.id)
  end
end
