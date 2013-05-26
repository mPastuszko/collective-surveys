class Survey
  attr_reader :survey_id
  alias :id :survey_id

  def self.find(db, survey_id)
    
    @db = db
    @survey_id = survey_id
  end

  def self.create(db, survey_id, kind, surveyer_name)
    @db = db
    @survey_id = survey_id || create_survey(kind)
    @kind = kind
  end

  def kind
    @db.get "survey:#{@survey_id}:module"
  end

  def update(data)
    @db.set "answer:#{@answer_id}:state", new_state(state)
  end

  protected

  def create_survey(kind)
    saved = false
    until saved
      survey_id = SecureRandom.urlsafe_base64
      saved = db.setnx "survey:#{survey_id}:surveyer_name", params[:surveyer_name]
    end
    db.set "survey:#{survey_id}:kind", kind
    
    case kind
    when 'synonyms', 'homophones'
      base_words = db.get "#{type}:base_words"
      db.set "survey:#{survey_id}:base_words", base_words
    when 'figures'
    end
    survey_id
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