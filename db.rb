require 'sequel'
require 'omniauth'
require 'omniauth-identity'
require_relative 'benchmark_configs'
require_relative 'omniauth-identity-sequel'

Sequel::Model.db = Sequel.sqlite('db.sqlite')

class User < Sequel::Model(:users)
  include OmniAuth::Identity::Models::Sequel
  plugin :validation_class_methods
  validates_uniqueness_of :name, :case_sensitive => false

  one_to_many :submissions
end

class Submission < Sequel::Model(:submissions)
  many_to_one :user
  one_to_many :benchmark_runs

  def validate
    super
    errors.add(:submission_variant, "should be one of #{SUBMISSION_VARIANTS.keys.join(', ')} but was `#{submission_variant}`") unless SUBMISSION_VARIANTS.has_key?(submission_variant)
  end

  def submission_type
    SUBMISSION_VARIANTS[submission_variant][:submission_type]
  end

  def tf
    SUBMISSION_VARIANTS[submission_variant][:tf]
  end

  def species
    SUBMISSION_VARIANTS[submission_variant][:species]
  end

  def benchmark_by_name(benchmark_name)
    benchmark_runs.detect{|benchmark_run|
      benchmark_run.benchmark_name == benchmark_name
    }
  end

  def scores
    benchmark_runs.flat_map(&:scores)
  end

  def most_recent?
    Submission.where(user_id: user_id, submission_variant: submission_variant).all?{|submission|
      submission.submission_time <= submission_time
    }
  end
end

class BenchmarkRun < Sequel::Model(:benchmark_runs)
  many_to_one :submission
  one_to_many :scores
  def metric_by_name(metric_name)
    scores.detect{|score_infos|
      score_infos.metric_name == metric_name
    }
  end
  def add_score_for_measure(measure_type_name, value)
    add_score(metric_name: measure_type_name, value: value, creation_time: Time.now)
  end
end

class Score < Sequel::Model(:scores)
  many_to_one :benchmark_run
  def submission; benchmark_run.submission; end
  def benchmark_name; benchmark_run.benchmark_name; end
  def full_metric_type; [benchmark_name, metric_name]; end
  def full_metric_name; "#{benchmark_name}:#{metric_name}"; end
end
