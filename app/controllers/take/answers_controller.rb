module Take
  class AnswersController < BaseController
    def upsert
      attempt = @assignment.attempts.find(params.require(:attempt_id))
      AttemptLifecycle.autosave!(
        attempt,
        normalize_answers(params[:answers]),
        expected_version: params[:lock_version]
      )

      render json: {
        ok: true,
        lock_version: attempt.lock_version,
        server_time: Time.current.iso8601,
        seconds_remaining: attempt.seconds_remaining,
        status: attempt.status
      }
    rescue AttemptLifecycle::Expired => e
      render json: { error: e.message, status: "expired" }, status: :unprocessable_entity
    rescue AttemptLifecycle::NotAllowed => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def normalize_answers(raw)
      case raw
      when Array
        raw
      when ActionController::Parameters, Hash
        raw.to_unsafe_h.map do |question_id, payload|
          { "question_id" => question_id, "payload" => payload }
        end
      else
        []
      end
    end
  end
end
