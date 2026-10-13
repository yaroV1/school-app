module Take
  class BaseController < ApplicationController
    allow_unauthenticated_access
    layout "student"

    before_action :set_assignment

    private

    def set_assignment
      @assignment = Assignment.includes(*assignment_includes).find_by!(access_token: params[:token])
      @exam = @assignment.exam
      @student = @assignment.student
    end

    def assignment_includes
      [ :student, { exam: :subject } ]
    end

    def device_key
      @device_key ||= cookies.signed[:take_device] || issue_device_key
    end

    def issue_device_key
      TokenGenerator.call.tap do |key|
        cookies.signed.permanent[:take_device] = { value: key, httponly: true, same_site: :lax }
      end
    end

    # A link is personal but carries no identity, so a forwarded one would let a second person sit
    # the same attempt. The first browser to start or continue the test keeps it; that also binds
    # attempts begun before the binding existed. A student who lost that browser gets a regenerated
    # link: the new token starts unbound, and the old tab's requests stop resolving at all, so it
    # cannot take the link back.
    def require_device
      reject_other_device unless @assignment.claim_device(device_key)
    end

    def reject_other_device
      redirect_to student_portal_path(token: @assignment.access_token), alert: t("take.errors.other_device")
    end
  end
end
