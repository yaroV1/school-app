class SubjectsController < ApplicationController
  SORTS = %w[created_desc created_asc title].freeze

  before_action :set_class_group, only: :create
  before_action :set_subject, only: %i[show stats edit update destroy]

  def show
    @sort = SORTS.include?(params[:sort]) ? params[:sort] : SORTS.first
    @query = params[:q].to_s.strip
    @sort_options = SORTS.map { |key| [ t("subjects.sort.#{key}"), key ] }
    @filtered = @query.present? || @sort != SORTS.first
    @exams = sorted_exams(filtered_exams)
  end

  def stats
    @stat_rows = @subject.student_stat_rows
    respond_to do |format|
      format.html
      format.csv { send_csv("#{@subject.name}.csv", stats_csv_headers, stats_csv_rows) }
    end
  end

  def create
    @subject = @class_group.subjects.new(subject_params)
    if @subject.save
      redirect_to @class_group, notice: t("subjects.flash.created")
    else
      @subjects = @class_group.subjects.includes(:exams).order(:name).to_a
      render "class_groups/show", status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @subject.update(subject_params)
      redirect_to @subject, notice: t("subjects.flash.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    class_group = @subject.class_group
    if @subject.destroy
      redirect_to class_group, notice: t("subjects.flash.deleted")
    else
      redirect_to @subject, alert: t("subjects.flash.has_tests")
    end
  end

  private

  # SQLite matches ASCII case-insensitively but not Cyrillic, and LOWER() leaves
  # Cyrillic untouched, so filtering and title sorting happen in Ruby.
  def filtered_exams
    exams = @subject.exams.includes(:questions).to_a
    return exams if @query.blank?

    needle = @query.downcase
    exams.select { |exam| exam.title.downcase.include?(needle) }
  end

  def sorted_exams(exams)
    case @sort
    when "created_asc" then exams.sort_by(&:created_at)
    when "title" then exams.sort_by { |exam| exam.title.downcase }
    else exams.sort_by(&:created_at).reverse
    end
  end

  def set_class_group
    @class_group = Current.user.class_groups.find(params[:class_group_id])
  end

  def set_subject
    @subject = Current.user.subjects.find(params[:id])
  end

  def stats_csv_headers
    [
      t("subjects.stats.student"),
      t("subjects.stats.tests"),
      t("subjects.stats.average"),
      t("subjects.stats.last")
    ]
  end

  def stats_csv_rows
    @stat_rows.map do |row|
      [
        row.student.name,
        row.assigned.positive? ? t("subjects.stats.progress", finished: row.finished, assigned: row.assigned) : "",
        row.average_percent.nil? ? "" : row.average_percent.to_s,
        csv_time(row.last_activity_at)
      ]
    end
  end

  def subject_params
    params.require(:subject).permit(:name)
  end
end
