class SurveyAnswer
  QuestionsPerStage = 10

  attr_reader :survey_id, :answer_id
  alias :id :answer_id

  def initialize(db, survey_id, answer_id)
    @db = db
    @survey_id = survey_id
    @answer_id = answer_id || create_answer(survey_id)
  end

  def state
    @db.get "answer:#{@answer_id}:state"
  end

  def question_num
    (@db.get("answer:#{@answer_id}:question_num") || 0).to_i
  end

  def next_question_num
    if question_num >= 0
      nqn = question_num + 1
      nqn % QuestionsPerStage == 0 ? -nqn : nqn
    else
      -question_num
    end
  end

  def kind
    @db.get "survey:#{@survey_id}:kind"
  end

  def answer_data
    JSON.load(@db.get("answer:#{@answer_id}:answer") || '{}')
  end

  def update(data)
    if data[:answer]
      ans = JSON.load(@db.get("answer:#{@answer_id}:answer") || '{}')
      ans.update(data[:answer])
      @db.set "answer:#{@answer_id}:answer", ans.to_json
    end
    @db.set "answer:#{@answer_id}:gender", data[:gender] if data[:gender]
    @db.set "answer:#{@answer_id}:age", data[:age] if data[:age]

    @db.set "answer:#{@answer_id}:state", (data[:state] || new_state(state))
    @db.set "answer:#{@answer_id}:question_num", data[:question_num] if data[:question_num]
  end

  protected

  def create_answer(survey_id)
    answer_id = @db.incr("answer:id")
    @db.set "answer:#{answer_id}:survey_id", survey_id
    @db.set "answer:#{answer_id}:state", new_state
    @db.sadd "survey:#{survey_id}:answers", answer_id
    answer_id
  end

  def new_state(previous_state = nil)
    case previous_state
    when 'welcome'
      'demographic_info'
    when 'demographic_info'
      "questions_#{kind}"
    when /questions/
      'finished'
    else
      'welcome'
    end
  end
end