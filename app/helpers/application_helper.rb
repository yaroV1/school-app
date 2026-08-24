module ApplicationHelper
  STATUS_BADGES = {
    "draft" => "badge-neutral",
    "published" => "badge-success",
    "closed" => "badge-warning",
    "not_started" => "badge-neutral",
    "in_progress" => "badge-info",
    "submitted" => "badge-success",
    "expired" => "badge-warning",
    "revoked" => "badge-danger",
    "abandoned" => "badge-neutral",
    "active" => "badge-success"
  }.freeze

  def btn_primary
    "btn btn-primary"
  end

  def btn_secondary
    "btn btn-secondary"
  end

  def btn_danger
    "btn btn-danger"
  end

  def field_class
    "field"
  end

  def ui_icon(name, class_name: "size-5")
    render "shared/icon", name: name.to_s, class_name: class_name
  end

  def subject_move_options(exam)
    grouped = Current.user.subjects.includes(:class_group)
      .sort_by { |subject| [ subject.class_group.name, subject.name ] }
      .group_by(&:class_group)
      .map { |group, subjects| [ group.name, subjects.map { |subject| [ subject.name, subject.id ] } ] }
    grouped_options_for_select(grouped, exam.subject_id)
  end

  # `aria-current` carries the active state, so highlighting is not tied to a
  # particular colour class.
  def nav_link_to(text, path)
    link_to text, path, class: "nav-link", aria: { current: ("page" if current_page?(path)) }
  end

  def tab_link_to(text, path, count: nil)
    link_to path, class: "tab", aria: { current: ("page" if current_page?(path)) } do
      parts = [ text ]
      parts << content_tag(:span, count, class: "tab-count") if count
      safe_join(parts, " ")
    end
  end

  # Same shape the countdown controller writes, so the server-rendered cell and
  # the ticking one never disagree.
  def countdown_display(seconds)
    return t("common.dash") if seconds.nil?

    format("%d:%02d", seconds / 60, seconds % 60)
  end

  # Scores are decimal(8,2), so a whole mark renders "1.0". That reads as machine output
  # on a sheet a parent is handed; a score is written 1, and 1.5 only when it is a half.
  def score_text(value)
    return t("common.dash") if value.nil?

    number = BigDecimal(value.to_s)
    number.frac.zero? ? number.to_i.to_s : number.to_s("F")
  end

  # Wet clay is a draft total; fired clay is the teacher-finalized stamp.
  # The two states are fill vs outline so hue never has to carry the meaning.
  def score_seal(grade, size: :md)
    return content_tag(:span, t("common.dash"), class: "text-ink-muted") if grade.nil?

    render "shared/score_seal", grade: grade, size: size.to_sym == :lg ? :lg : :md
  end

  # First and last word, because a Ukrainian roster writes surname-first as
  # often as the reverse — either order yields the same two letters.
  def initials(name)
    name.to_s.split.values_at(0, -1).compact.uniq.filter_map { |word| word[0] }.join.upcase
  end

  def status_badge(status)
    variant = STATUS_BADGES.fetch(status.to_s, "badge-neutral")
    content_tag(:span, t("statuses.#{status}"), class: "badge #{variant}")
  end

  def take_brief(exam, student, attempts_used)
    t("take.brief",
      name: student.name,
      questions: t("exams.questions_count", count: exam.questions.size),
      time: exam.time_limit_sec ? t("take.brief_time", count: exam.time_limit_sec / 60) : t("take.brief_untimed"),
      used: attempts_used,
      max: exam.max_attempts)
  end

  # Ordering stores a full permutation as soon as the first autosave lands, so a
  # saved row counts as started even if the student never reordered.
  def answer_started?(question, answer)
    return false if answer.nil?

    if question.mcq?
      answer.option_id.present?
    elsif question.ordering?
      answer.order_ids.any?
    elsif question.matching?
      answer.pairs.values.any?(&:present?)
    else
      answer.text_response.present?
    end
  end
end
