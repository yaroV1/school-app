# Idempotent demo data for local app testing.
#   bin/rails db:seed
#   # or fresh:
#   bin/rails db:reset

teacher = User.find_or_create_by!(email_address: "teacher@example.com") do |user|
  user.password = "password123"
end

# ---------------------------------------------------------------------------
# Students
# ---------------------------------------------------------------------------
student_attrs = [
  { name: "Ada Lovelace", email: "ada@example.com" },
  { name: "Alan Turing", email: "alan@example.com" },
  { name: "Grace Hopper", email: "grace@example.com" },
  { name: "Katherine Johnson", email: "katherine@example.com" },
  { name: "Linus Torvalds", email: "linus@example.com" },
  { name: "Margaret Hamilton", email: "margaret@example.com" },
  { name: "Tim Berners-Lee", email: "tim@example.com" },
  { name: "Donald Knuth", email: "donald@example.com" },
  { name: "Barbara Liskov", email: "barbara@example.com" },
  { name: "Edsger Dijkstra", email: "edsger@example.com" }
]

students = student_attrs.map do |attrs|
  teacher.students.find_or_create_by!(name: attrs[:name]) do |s|
    s.email = attrs[:email]
  end.tap do |s|
    s.update!(email: attrs[:email], archived_at: nil) if s.email != attrs[:email] || s.archived?
  end
end

# ---------------------------------------------------------------------------
# Classes
# ---------------------------------------------------------------------------
class_a = teacher.class_groups.find_or_create_by!(name: "Class 10-A")
class_b = teacher.class_groups.find_or_create_by!(name: "Class 10-B")

class_a.replace_members!(students.first(6).map(&:id))
class_b.replace_members!(students.last(5).map(&:id))

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def seed_exam!(teacher, attrs)
  exam = teacher.exams.find_or_initialize_by(title: attrs[:title])
  exam.assign_attributes(
    description: attrs[:description],
    time_limit_sec: attrs[:time_limit_sec],
    max_attempts: attrs[:max_attempts] || 1,
    available_from: attrs[:available_from],
    available_until: attrs[:available_until]
  )
  exam.status = :draft if exam.new_record?
  exam.save!

  if exam.questions.none?
    attrs[:questions].each_with_index do |q, index|
      exam.questions.create!(
        question_type: q[:type],
        prompt: q[:prompt],
        points: q[:points] || 1,
        position: index,
        config: q[:config] || {}
      )
    end
  end

  exam
end

def seed_assignments!(exam, students)
  students.each do |student|
    exam.assignments.find_or_create_by!(student: student)
  end
end

# ---------------------------------------------------------------------------
# Tests (Exam records)
# ---------------------------------------------------------------------------

# 1) Published algebra quiz — assigned to Class 10-A, timed, ready to take
algebra = seed_exam!(teacher,
  title: "Algebra Basics",
  description: "Short check on linear equations and expressions. Calculators allowed.",
  time_limit_sec: 15 * 60,
  max_attempts: 1,
  available_from: 1.day.ago,
  available_until: 7.days.from_now,
  questions: [
    {
      type: :mcq,
      prompt: "Solve for x: 2x + 4 = 10",
      points: 1,
      config: {
        "options" => [
          { "id" => "a1", "text" => "x = 2", "is_correct" => false },
          { "id" => "a2", "text" => "x = 3", "is_correct" => true },
          { "id" => "a3", "text" => "x = 4", "is_correct" => false },
          { "id" => "a4", "text" => "x = 5", "is_correct" => false }
        ]
      }
    },
    {
      type: :mcq,
      prompt: "Which expression is equivalent to 3(x + 2)?",
      points: 1,
      config: {
        "options" => [
          { "id" => "b1", "text" => "3x + 2", "is_correct" => false },
          { "id" => "b2", "text" => "3x + 6", "is_correct" => true },
          { "id" => "b3", "text" => "x + 6", "is_correct" => false },
          { "id" => "b4", "text" => "3x + 5", "is_correct" => false }
        ]
      }
    },
    {
      type: :short_text,
      prompt: "In one sentence, what does the slope of a line represent?",
      points: 2,
      config: {
        "rubric" => "Mentions rate of change / rise over run.",
        "model_answer" => "How steep the line is; change in y over change in x."
      }
    },
    {
      type: :open,
      prompt: "A taxi charges $3 to start and $2 per kilometer. Write an equation for the cost C after k kilometers, then find the cost for 7 km.",
      points: 3,
      config: {
        "rubric" => "Equation C = 3 + 2k (or equivalent) and cost 17.",
        "model_answer" => "C = 3 + 2k; for k=7, C=17."
      }
    }
  ]
)
algebra.publish! unless algebra.published?
seed_assignments!(algebra, class_a.students)

# 2) Published history quiz — Class 10-B, 2 attempts, untimed
history = seed_exam!(teacher,
  title: "World War II — Intro",
  description: "Open-book friendly. Use short answers where asked.",
  time_limit_sec: nil,
  max_attempts: 2,
  questions: [
    {
      type: :mcq,
      prompt: "In which year did World War II begin in Europe?",
      points: 1,
      config: {
        "options" => [
          { "id" => "h1", "text" => "1914", "is_correct" => false },
          { "id" => "h2", "text" => "1939", "is_correct" => true },
          { "id" => "h3", "text" => "1941", "is_correct" => false },
          { "id" => "h4", "text" => "1945", "is_correct" => false }
        ]
      }
    },
    {
      type: :short_text,
      prompt: "Name one major Allied power.",
      points: 1,
      config: { "rubric" => "e.g. UK, USA, USSR, China, France", "model_answer" => "United Kingdom / USA / USSR" }
    },
    {
      type: :open,
      prompt: "In a short paragraph, explain one cause of World War II.",
      points: 3,
      config: {
        "rubric" => "Clear cause with brief explanation (Treaty of Versailles, expansionism, etc.).",
        "model_answer" => "Unresolved grievances after WWI / aggressive expansion by Axis powers."
      }
    }
  ]
)
history.publish! unless history.published?
seed_assignments!(history, class_b.students)

# 3) Draft test — not published yet (for builder UI)
seed_exam!(teacher,
  title: "Biology Cells (draft)",
  description: "Work in progress — do not assign yet.",
  time_limit_sec: 20 * 60,
  max_attempts: 1,
  questions: [
    {
      type: :mcq,
      prompt: "Which organelle is known as the powerhouse of the cell?",
      points: 1,
      config: {
        "options" => [
          { "id" => "c1", "text" => "Nucleus", "is_correct" => false },
          { "id" => "c2", "text" => "Mitochondrion", "is_correct" => true },
          { "id" => "c3", "text" => "Ribosome", "is_correct" => false },
          { "id" => "c4", "text" => "Golgi apparatus", "is_correct" => false }
        ]
      }
    },
    {
      type: :short_text,
      prompt: "What is the main function of the cell membrane?",
      points: 2,
      config: { "rubric" => "Controls what enters/leaves the cell.", "model_answer" => "Selective barrier / transport control" }
    }
  ]
)

# 4) Closed test with one submitted attempt (for results / grading UI)
closed = seed_exam!(teacher,
  title: "Quick Warm-up (closed)",
  description: "Already finished session — use for grading practice.",
  time_limit_sec: 5 * 60,
  max_attempts: 1,
  questions: [
    {
      type: :mcq,
      prompt: "2 + 2 = ?",
      points: 1,
      config: {
        "options" => [
          { "id" => "w1", "text" => "3", "is_correct" => false },
          { "id" => "w2", "text" => "4", "is_correct" => true },
          { "id" => "w3", "text" => "5", "is_correct" => false }
        ]
      }
    },
    {
      type: :open,
      prompt: "Write one sentence about why practice helps learning.",
      points: 2,
      config: { "rubric" => "Any reasonable reflective sentence.", "model_answer" => "Practice strengthens memory and skill." }
    }
  ]
)
closed.publish! unless closed.published? || closed.closed?
demo_student = students.first
assignment = closed.assignments.find_or_create_by!(student: demo_student)
if assignment.attempts.none?
  attempt = AttemptLifecycle.start!(assignment)
  AttemptLifecycle.autosave!(attempt, [
    { "question_id" => closed.questions.first.id, "payload" => { "option_id" => "w2" } },
    { "question_id" => closed.questions.second.id, "payload" => { "text" => "Practice helps ideas stick in long-term memory." } }
  ])
  AttemptLifecycle.submit!(attempt)
end
closed.close! unless closed.closed?

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
puts ""
puts "Seeded demo data"
puts "================"
puts "Teacher login:  teacher@example.com / password123"
puts "Classes:        #{teacher.class_groups.order(:name).pluck(:name).join(', ')}"
puts "Students:       #{teacher.students.active.count}"
puts "Tests:"
teacher.exams.order(:title).each do |exam|
  links = exam.assignments.limit(2).map { |a| "http://localhost:3000/t/#{a.access_token}" }
  puts "  - [#{exam.status}] #{exam.title} (#{exam.assignments.count} links)"
  links.each { |url| puts "      sample: #{url}" }
end
puts ""
puts "Suggested path:"
puts "  1) Sign in → Tests → Algebra Basics → Live board / Assign"
puts "  2) Open a sample student link above in a private window"
puts "  3) Grade Quick Warm-up (closed) under Results"
puts ""
