class SurveyAnswer
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

  def kind
    @db.get "survey:#{@survey_id}:module"
  end

  def update(data)
    @db.set "answer:#{@answer_id}:state", new_state(state)
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
      "questions_#{kind}"
    when /questions/
      'demographic_info'
    when 'demographic_info'
      'thanks'
    when 'thanks'
      'already_participated'
    else
      'welcome'
    end
  end
end