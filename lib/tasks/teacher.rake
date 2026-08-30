# The only way to mint a teacher account: there is no registration route, and password reset
# needs a mail server production.rb does not configure yet. On a deployed server run it as
#   bin/kamal app exec --interactive --reuse "bin/rails teacher:create"
# where --interactive is what gives the process a TTY — and the TTY is what keeps the password
# out of the command line, the process list, and shell history, the way ENV would not.
namespace :teacher do
  desc "Create a teacher account, prompting for the email and password"
  task create: :environment do
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

    password = ask_secret.call(I18n.t("tasks.teacher_create.password", minimum: User::MINIMUM_PASSWORD_LENGTH))
    # has_secure_password would catch this too, but only through rails-i18n's confirmation
    # message, which prefixes an untranslated attribute name. The reset form already states the
    # same mistake in Ukrainian, so ask here and reuse that sentence.
    abort I18n.t("auth.passwords.mismatch") if password != ask_secret.call(I18n.t("tasks.teacher_create.repeat"))

    # Every other rule is the model's — the address, and the password floor it now carries — so
    # there is one place to change any of them and no second copy to drift.
    teacher = User.new(email_address: email, password: password)
    abort teacher.errors.full_messages.to_sentence unless teacher.save

    $stdout.puts I18n.t("tasks.teacher_create.created", email: teacher.email_address, id: teacher.id)
  end
end
