class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: t("auth.try_again_later") }

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: t("auth.passwords.reset_sent")
  end

  def edit
  end

  def update
    if @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: t("auth.passwords.reset_success")
    else
      # A mismatch was the only way this could fail until the password grew a length floor, and
      # a teacher told "паролі не збігаються" about two identical short ones would retype them
      # forever. rails-i18n words the length refusal well; its confirmation message does not, so
      # that one keeps the curated sentence.
      redirect_to edit_password_path(params[:token]),
        alert: @user.errors.where(:password).first&.full_message || t("auth.passwords.mismatch")
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: t("auth.passwords.invalid_link")
    end
end
