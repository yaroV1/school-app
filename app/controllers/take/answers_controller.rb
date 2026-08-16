module Take
  class AnswersController < BaseController
    def upsert
      attempt = @assignment.attempts.find(params.require(:attempt_id))
      AttemptLifecycle.autosave!(attempt, normalize_answers(params[:answers]))

      render json: {
        ok: true,
        server_time: Time.current.iso8601,
        seconds_remaining: attempt.seconds_remaining,
        status: attempt.status
      }
    rescue AttemptLifecycle::Expired => e
      render json: { error: e.message, status: "expired" }, status: :unprocessable_entity
    rescue AttemptLifecycle::NotAllowed => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue AttemptLifecycle::Conflict => e
      # autosave_controller.js renders data.error on any non-ok response, so the student sees
      # this message and the next tick retries. Without the rescue it is an unhandled 500.
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
