class RoastLogItem < ActiveRecord::Base

  def as_json(options={})
    # h = super(options)
    # super(:only => [:id,:learned,:e_factor,:repetitions,:next_test_at],
    #       :include => {
    #           :srcard => {:only => [:front,:back]}
    #       }
    # )
    h = super(:only => [:t,:et,:bt, :ror] )
    #h[:count] = self.count_cards
    h
  end

end
