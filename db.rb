require 'sequel'
require 'omniauth'
require 'omniauth-identity'
require_relative 'omniauth-identity-sequel'

Sequel::Model.db = Sequel.sqlite('db.sqlite')

class User < Sequel::Model(:users)
  include OmniAuth::Identity::Models::Sequel
  plugin :validation_class_methods
  validates_uniqueness_of :name, :case_sensitive => false

  one_to_many :submissions
  def send_submission(ticket:, submission_variant:)
    add_submission(ticket: ticket, submission_variant: submission_variant, creation_time: Time.now)
  end
end

class Submission < Sequel::Model(:submissions)
  many_to_one :user
  many_to_one :submission_variant
  one_to_many :benchmark_runs
  def tf; submission_variant.tf; end
  def species; submission_variant.species; end
  def submission_type; submission_variant.submission_type; end
  def scores
    benchmark_runs.flat_map(&:scores)
  end
  def scores_by_benchmark
    scores.group_by(&:benchmark).sort_by{|benchmark, scores| benchmark.name }
  end
end

class SubmissionVariant < Sequel::Model(:submission_variants)
  one_to_many :submissions
end

class Benchmark < Sequel::Model(:benchmarks)
  one_to_many :measure_types
  one_to_many :benchmark_runs
  def measure_type_by_name(measure_type_name)
    measure_types_dataset.first(name: measure_type_name)
  end
end

class BenchmarkRun < Sequel::Model(:benchmark_runs)
  many_to_one :submission
  many_to_one :benchmark
  one_to_many :scores
  def measure_types; benchmark.measure_types; end
  def add_score_for_measure(measure_type_name, value)
    measure_type = benchmark.measure_type_by_name(measure_type_name)
    add_score(measure_type_id: measure_type.id, value: value, creation_time: Time.now)
  end
end

class Score < Sequel::Model(:scores)
  many_to_one :benchmark_run
  many_to_one :measure_type
  def benchmark; measure_type.benchmark; end
  def measure_name; measure_type.full_name; end
end

class MeasureType < Sequel::Model(:measure_types)
  one_to_many :scores
  many_to_one :benchmark
  def full_name
    "#{benchmark.name}:#{name}"
  end
  def self.grouped_by_benchmark_and_sorted
    Benchmark.sort_by(&:name).map{|benchmark|
      [benchmark, benchmark.measure_types.sort_by(&:name)]
    }
  end
end
