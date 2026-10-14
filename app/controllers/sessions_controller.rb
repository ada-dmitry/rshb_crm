class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  # The local demo runs one web process; keep throttling enabled even with NullStore.
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new
  rate_limit to: 10, within: 3.minutes, only: :create, store: RATE_LIMIT_STORE,
    with: -> { redirect_to new_session_path, alert: "Слишком много попыток. Попробуйте через 3 минуты." }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "Неверная почта или пароль."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
