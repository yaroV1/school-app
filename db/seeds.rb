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

algebra_subject = class_a.subjects.find_or_create_by!(name: "Алгебра")
biology_subject = class_a.subjects.find_or_create_by!(name: "Біологія")
ukraine_history = class_a.subjects.find_or_create_by!(name: "Історія України")
world_history = class_b.subjects.find_or_create_by!(name: "Всесвітня історія")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def seed_exam!(teacher, attrs)
  exam = teacher.exams.find_or_initialize_by(title: attrs[:title])
  exam.assign_attributes(
    subject: attrs.fetch(:subject),
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
  subject: algebra_subject,
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
  subject: world_history,
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
  subject: biology_subject,
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
    },
    {
      type: :source,
      prompt: "In 2–3 sentences, explain what this passage says about the nucleus.",
      points: 3,
      config: {
        "source" => "The nucleus is a membrane-bound organelle that contains the cell's genetic material. It controls growth and reproduction by regulating gene expression. Most eukaryotic cells have a single nucleus.",
        "rubric" => "Mentions genetic material / control of the cell.",
        "model_answer" => "The nucleus stores DNA and directs cell activity through gene expression."
      }
    }
  ]
)

# 4) Closed test with one submitted attempt (for results / grading UI)
closed = seed_exam!(teacher,
  subject: algebra_subject,
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

# 5) Published chronology + matching demo
chrono = seed_exam!(teacher,
  subject: ukraine_history,
  title: "Chronology & matching",
  description: "Reorder events and match facts. Auto-scored.",
  time_limit_sec: 10 * 60,
  max_attempts: 1,
  available_from: 1.day.ago,
  available_until: 14.days.from_now,
  questions: [
    {
      type: :ordering,
      prompt: "Put these events in chronological order.",
      points: 2,
      config: {
        "items" => [
          { "id" => "e1", "text" => "World War I begins" },
          { "id" => "e2", "text" => "The Treaty of Versailles is signed" },
          { "id" => "e3", "text" => "World War II begins in Europe" },
          { "id" => "e4", "text" => "The United Nations is founded" }
        ]
      }
    },
    {
      type: :matching,
      prompt: "Match each person with the country they led.",
      points: 3,
      config: {
        "left" => [
          { "id" => "l1", "text" => "Winston Churchill" },
          { "id" => "l2", "text" => "Franklin D. Roosevelt" },
          { "id" => "l3", "text" => "Joseph Stalin" }
        ],
        "right" => [
          { "id" => "r1", "text" => "United Kingdom" },
          { "id" => "r2", "text" => "United States" },
          { "id" => "r3", "text" => "Soviet Union" }
        ],
        "pairs" => { "l1" => "r1", "l2" => "r2", "l3" => "r3" }
      }
    }
  ]
)
chrono.publish! unless chrono.published?
seed_assignments!(chrono, class_a.students)

# ---------------------------------------------------------------------------
# 10 mixed-type tests on Class 10-A / Алгебра (search/sort demo + all types)
# ---------------------------------------------------------------------------
def seed_mcq(prompt, choices, points: 1)
  options = choices.each_with_index.map do |choice, index|
    { "id" => "o#{index + 1}", "text" => choice[:text], "is_correct" => choice[:correct] == true }
  end
  { type: :mcq, prompt: prompt, points: points, config: { "options" => options } }
end

def seed_short(prompt, rubric:, model:, points: 2)
  { type: :short_text, prompt: prompt, points: points, config: { "rubric" => rubric, "model_answer" => model } }
end

def seed_open(prompt, rubric:, model:, points: 3)
  { type: :open, prompt: prompt, points: points, config: { "rubric" => rubric, "model_answer" => model } }
end

def seed_ordering(prompt, items, points: 2)
  {
    type: :ordering,
    prompt: prompt,
    points: points,
    config: { "items" => items.each_with_index.map { |text, i| { "id" => "e#{i + 1}", "text" => text } } }
  }
end

def seed_matching(prompt, pairs, points: 3)
  left = []
  right = []
  key = {}
  pairs.each_with_index do |(l_text, r_text), i|
    lid = "l#{i + 1}"
    rid = "r#{i + 1}"
    left << { "id" => lid, "text" => l_text }
    right << { "id" => rid, "text" => r_text }
    key[lid] = rid
  end
  { type: :matching, prompt: prompt, points: points, config: { "left" => left, "right" => right, "pairs" => key } }
end

def seed_source(prompt, source:, rubric:, model:, points: 3)
  {
    type: :source,
    prompt: prompt,
    points: points,
    config: { "source" => source, "rubric" => rubric, "model_answer" => model }
  }
end

algebra_pack = [
  {
    title: "Лінійні рівняння",
    description: "Розв’язування рівнянь виду ax + b = c.",
    time_limit_sec: 15 * 60,
    questions: [
      seed_mcq("Розв’яжіть: 2x + 4 = 10", [
        { text: "x = 2", correct: false }, { text: "x = 3", correct: true },
        { text: "x = 4", correct: false }, { text: "x = 5", correct: false }
      ]),
      seed_short("Що означає корінь лінійного рівняння?", rubric: "Значення змінної, яке перетворює рівняння на тотожність.", model: "Число, яке задовольняє рівняння."),
      seed_ordering("Упорядкуйте кроки розв’язання 3x − 6 = 9.", [
        "Додати 6 до обох частин", "Отримати 3x = 15", "Поділити обидві частини на 3", "x = 5"
      ]),
      seed_matching("Увідповідніть рівняння та корінь.", [
        [ "x + 5 = 8", "x = 3" ],
        [ "2x = 10", "x = 5" ],
        [ "x − 4 = 0", "x = 4" ]
      ])
    ]
  },
  {
    title: "Квадратні рівняння",
    description: "Дискримінант, формула коренів, теорема Вієта.",
    time_limit_sec: 20 * 60,
    questions: [
      seed_mcq("Скільки дійсних коренів має x² + 1 = 0?", [
        { text: "Жодного", correct: true }, { text: "Один", correct: false },
        { text: "Два", correct: false }, { text: "Нескінченно багато", correct: false }
      ]),
      seed_open("Поясніть, як дискримінант визначає кількість дійсних коренів.",
        rubric: "D>0 два, D=0 один, D<0 немає дійсних.",
        model: "Якщо D > 0 — два різні корені; D = 0 — один (кратний); D < 0 — дійсних коренів немає."),
      seed_source("Коротко сформулюйте висновок з уривка про формулу коренів.",
        source: "Для рівняння ax² + bx + c = 0 (a ≠ 0) корені знаходять за формулою x = (−b ± √D) / (2a), де D = b² − 4ac. Формула працює над дійсними числами лише коли D ≥ 0.",
        rubric: "Згадує формулу та умову D ≥ 0.",
        model: "Корені шукають через дискримінант; дійсні корені є лише при D ≥ 0."),
      seed_matching("Увідповідніть величину та її зміст.", [
        [ "D = b² − 4ac", "дискримінант" ],
        [ "x₁ + x₂ = −b/a", "сума коренів" ],
        [ "x₁ · x₂ = c/a", "добуток коренів" ]
      ])
    ]
  },
  {
    title: "Звичайні дроби",
    description: "Скорочення, порівняння, дії з дробами.",
    time_limit_sec: 15 * 60,
    questions: [
      seed_mcq("Який дріб дорівнює 2/4?", [
        { text: "1/3", correct: false }, { text: "1/2", correct: true },
        { text: "2/3", correct: false }, { text: "3/4", correct: false }
      ]),
      seed_short("Як знайти спільний знаменник дробів 1/4 і 1/6?", rubric: "НСК знаменників 12.", model: "НСК(4, 6) = 12"),
      seed_ordering("Упорядкуйте кроки додавання 1/4 + 1/6.", [
        "Знайти НСК знаменників (12)", "Переписати як 3/12 + 2/12", "Додати чисельники", "Отримати 5/12"
      ]),
      seed_open("Поясніть, чому не можна додавати дроби з різними знаменниками «напряму».",
        rubric: "Різні частини цілого; треба спільний знаменник.",
        model: "Доданки мають бути однаковими частинами цілого, тому спочатку зводять до спільного знаменника.")
    ]
  },
  {
    title: "Відсотки",
    description: "Знаходження відсотка від числа та збільшення/зменшення.",
    time_limit_sec: 12 * 60,
    questions: [
      seed_mcq("Скільки становить 10% від 250?", [
        { text: "10", correct: false }, { text: "15", correct: false },
        { text: "25", correct: true }, { text: "40", correct: false }
      ]),
      seed_matching("Увідповідніть запис і значення.", [
        [ "10%", "0,1" ],
        [ "25%", "1/4" ],
        [ "50%", "0,5" ]
      ]),
      seed_source("Який спосіб обчислення відсотка описує текст?",
        source: "Щоб знайти p відсотків від числа a, множать a на p/100. Наприклад, 20% від 80 це 80 · 0,2 = 16. Збільшити число на p% означає помножити його на (1 + p/100).",
        rubric: "Множення на p/100; збільшення — на (1 + p/100).",
        model: "Відсоток від числа — це множення на p/100; збільшення на p% — множення на 1 + p/100."),
      seed_short("Товар коштував 200 грн і подорожчав на 15%. Яка нова ціна?", rubric: "200 × 1,15 = 230.", model: "230 грн")
    ]
  },
  {
    title: "Арифметична прогресія",
    description: "Різниця прогресії, n-й член, сума перших n членів.",
    time_limit_sec: 18 * 60,
    questions: [
      seed_ordering("Упорядкуйте члени прогресії 2, 5, 8, … за зростанням індексу.", [
        "a₁ = 2", "a₂ = 5", "a₃ = 8", "a₄ = 11"
      ]),
      seed_mcq("Яка різниця прогресії 3, 7, 11, 15, …?", [
        { text: "2", correct: false }, { text: "3", correct: false },
        { text: "4", correct: true }, { text: "5", correct: false }
      ]),
      seed_matching("Увідповідніть формулу та величину.", [
        [ "aₙ = a₁ + (n − 1)d", "n-й член" ],
        [ "Sₙ = n(a₁ + aₙ)/2", "сума n членів" ],
        [ "d = aₙ₊₁ − aₙ", "різниця прогресії" ]
      ]),
      seed_open("Знайдіть 10-й член прогресії 1, 4, 7, … і коротко запишіть хід розв’язання.",
        rubric: "a₁=1, d=3, a₁₀=1+9·3=28.",
        model: "a₁₀ = 1 + 9·3 = 28.")
    ]
  },
  {
    title: "Лінійна функція",
    description: "Графік y = kx + b, кутовий коефіцієнт, перетин з осями.",
    time_limit_sec: 15 * 60,
    questions: [
      seed_source("Що текст каже про роль k у формулі y = kx + b?",
        source: "Лінійна функція має вигляд y = kx + b. Число k називають кутовим коефіцієнтом: воно показує, наскільки змінюється y, коли x збільшується на 1. Число b — це ордината точки перетину графіка з віссю y.",
        rubric: "k — нахил / зміна y на одиницю x.",
        model: "k показує нахил прямої: зміну y при зростанні x на 1."),
      seed_mcq("У якій точці графік y = 2x + 3 перетинає вісь y?", [
        { text: "(0; 2)", correct: false }, { text: "(0; 3)", correct: true },
        { text: "(3; 0)", correct: false }, { text: "(2; 0)", correct: false }
      ]),
      seed_short("Що означає, що k < 0?", rubric: "Функція спадна / пряма йде вниз.", model: "Пряма спадна."),
      seed_ordering("Упорядкуйте кроки побудови графіка y = x + 1.", [
        "Знайти точку (0; 1)", "Знайти ще одну точку, наприклад (1; 2)", "Поставити точки на координатній площині", "Провести пряму через точки"
      ])
    ]
  },
  {
    title: "Лінійні нерівності",
    description: "Знаки нерівності та множина розв’язків на прямій.",
    time_limit_sec: 12 * 60,
    questions: [
      seed_mcq("Яка множина є розв’язком x > 2?", [
        { text: "x = 2", correct: false }, { text: "усі числа менші за 2", correct: false },
        { text: "усі числа більші за 2", correct: true }, { text: "лише цілі числа більші за 2", correct: false }
      ]),
      seed_matching("Увідповідніть нерівність та інтервал.", [
        [ "x ≥ 0", "[0; +∞)" ],
        [ "x < 3", "(−∞; 3)" ],
        [ "1 < x < 5", "(1; 5)" ]
      ]),
      seed_open("Поясніть, чому при множенні нерівності на від’ємне число знак змінюють на протилежний.",
        rubric: "Множення на від’ємне розвертає порядок на прямій.",
        model: "Від’ємний множник змінює порядок чисел, тому знак нерівності треба обернути."),
      seed_source("Яке правило з уривка треба застосувати до −2x > 6?",
        source: "Лінійну нерівність розв’язують так само, як рівняння, але з однією відмінністю: якщо обидві частини множать або ділять на від’ємне число, знак нерівності змінюють на протилежний. Приклад: −x > 2 рівносильно x < −2.",
        rubric: "Поділити на −2 і змінити знак: x < −3.",
        model: "Ділимо на −2 і змінюємо знак, отримуємо x < −3.")
    ]
  },
  {
    title: "Степені й корені",
    description: "Властивості степеня з натуральним показником і квадратний корінь.",
    time_limit_sec: 15 * 60,
    questions: [
      seed_mcq("Чому дорівнює 2³?", [
        { text: "6", correct: false }, { text: "8", correct: true },
        { text: "9", correct: false }, { text: "16", correct: false }
      ]),
      seed_ordering("Упорядкуйте значення за зростанням.", [
        "√1", "√4", "√9", "√16"
      ]),
      seed_short("Чому дорівнює √49?", rubric: "7 (арифметичний корінь).", model: "7"),
      seed_matching("Увідповідніть вираз і значення.", [
        [ "5²", "25" ],
        [ "10⁰", "1" ],
        [ "√81", "9" ]
      ])
    ]
  },
  {
    title: "Текстові задачі",
    description: "Складання рівняння за умовою задачі.",
    time_limit_sec: 20 * 60,
    questions: [
      seed_open("Число збільшили на 7 і отримали 20. Складіть рівняння і знайдіть число.",
        rubric: "x + 7 = 20, x = 13.",
        model: "x + 7 = 20; x = 13."),
      seed_mcq("Квиток коштує 80 грн, учнівський — на 25% дешевший. Скільки коштує учнівський?", [
        { text: "20 грн", correct: false }, { text: "55 грн", correct: false },
        { text: "60 грн", correct: true }, { text: "75 грн", correct: false }
      ]),
      seed_source("Яке рівняння відповідає цій задачі?",
        source: "У двох коробках разом 18 олівців. У першій на 4 олівці більше, ніж у другій. Скільки олівців у кожній коробці? Якщо в другій x олівців, то в першій x + 4, а разом x + (x + 4) = 18.",
        rubric: "2x + 4 = 18, x = 7 і 11.",
        model: "x + (x + 4) = 18 → x = 7, у першій 11."),
      seed_matching("Увідповідніть умову та рівняння.", [
        [ "Число втричі більше за 5", "x = 3 · 5" ],
        [ "Сума числа і 8 дорівнює 20", "x + 8 = 20" ],
        [ "Половина числа дорівнює 6", "x / 2 = 6" ]
      ])
    ]
  },
  {
    title: "Підсумкова контрольна з алгебри",
    description: "Усі типи завдань: вибір, коротка відповідь, відкрите, порядок, відповідність, робота з текстом.",
    time_limit_sec: 30 * 60,
    max_attempts: 1,
    questions: [
      seed_mcq("Яке з чисел є розв’язком рівняння 5x = 20?", [
        { text: "2", correct: false }, { text: "4", correct: true },
        { text: "5", correct: false }, { text: "15", correct: false }
      ]),
      seed_short("Запишіть формулу дискримінанта квадратного рівняння ax² + bx + c = 0.",
        rubric: "D = b² − 4ac", model: "D = b² − 4ac"),
      seed_open("Складіть короткий план розв’язання текстової задачі на складання рівняння.",
        rubric: "Позначити невідоме, скласти рівняння, розв’язати, перевірити.",
        model: "1) ввести змінну; 2) перекласти умову рівнянням; 3) розв’язати; 4) перевірити за змістом задачі."),
      seed_ordering("Упорядкуйте етапи розв’язання квадратного рівняння.", [
        "Записати коефіцієнти a, b, c", "Обчислити дискримінант", "Перевірити знак D", "Записати корені за формулою"
      ]),
      seed_matching("Увідповідніть тип завдання та що воно перевіряє.", [
        [ "Тест із варіантами", "вибір правильної відповіді" ],
        [ "Упорядкування", "правильна послідовність кроків" ],
        [ "Відповідність", "зв’язок між двома списками" ]
      ]),
      seed_source("Сформулюйте головну думку уривка одним реченням.",
        source: "Алгебра вчить записувати загальні залежності мовою формул. Рівняння допомагає знайти невідоме, нерівність — описати множину можливих значень, а функція — побачити, як одна величина змінюється разом з іншою.",
        rubric: "Алгебра описує залежності формулами / рівняннями / функціями.",
        model: "Алгебра дає мову формул, щоб знаходити невідоме й описувати зміну величин.")
    ]
  }
]

algebra_pack.each do |attrs|
  exam = seed_exam!(teacher, {
    subject: algebra_subject,
    max_attempts: 1,
    available_from: 1.day.ago,
    available_until: 14.days.from_now
  }.merge(attrs))
  exam.publish! unless exam.published? || exam.closed?
  seed_assignments!(exam, class_a.students)
end

teacher.class_groups.each do |group|
  group.subjects.where(name: "Предмет").find_each do |subject|
    subject.destroy if subject.exams.none?
  end
end

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
puts ""
puts "Seeded demo data"
puts "================"
puts "Teacher login:  teacher@example.com / password123"
puts "Classes:        #{teacher.class_groups.order(:name).pluck(:name).join(', ')}"
puts "Subjects:       #{Subject.joins(:class_group).where(class_groups: { teacher_id: teacher.id }).order(:name).map { |s| "#{s.class_group.name}: #{s.name}" }.join(', ')}"
puts "Students:       #{teacher.students.active.count}"
puts "Tests:"
teacher.exams.order(:title).each do |exam|
  links = exam.assignments.limit(2).map { |a| "http://localhost:3000/t/#{a.access_token}" }
  puts "  - [#{exam.status}] #{exam.subject.name} / #{exam.title} (#{exam.assignments.count} links)"
  links.each { |url| puts "      sample: #{url}" }
end
puts ""
puts "Suggested path:"
puts "  1) Sign in → Classes → Class 10-A → Алгебра → Algebra Basics"
puts "  2) Open a sample student link above in a private window"
puts "  3) Grade Quick Warm-up (closed) under Results"
puts ""
