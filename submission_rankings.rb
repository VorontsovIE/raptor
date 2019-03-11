def best_submissions(variant_submissions)
  variant_submissions
end

def rank_by(objects, greater_is_better:, use_group_size: false, &block)
  block = ->(obj){ obj }  unless block_given?
  groups = objects.group_by(&block)

  sorted_groups = groups.select{|val, group| val }.sort + groups.reject{|val, group| val }.to_a
  sorted_groups.reverse!  if greater_is_better
  object_with_ranks = []
  rank = 1
  sorted_groups.each{|_value, group|
    group.each{|obj|
      object_with_ranks << {object: obj, rank: rank}
    }
    rank += use_group_size ? group.size : 1
  }
  object_with_ranks
end

def submission_ranks(submissions)
  raise 'Submissions should be of the same submission_variant'  if submissions.map(&:submission_variant).uniq.size > 1
  submissions.flat_map(&:scores).group_by{|score|
    [score.benchmark_name, score.metric_name]
  }.flat_map{|(bm_name, metric_name), scores|
    greater_is_better = benchmark_by_name(bm_name)[:metrics][metric_name][:greater_is_better]
    rank_by(scores, greater_is_better: greater_is_better, &:value).map{|rank_info|
      {submission: rank_info[:object].submission, benchmark_name: bm_name, metric_name: metric_name, rank: rank_info[:rank]}
    }
  }.group_by{|rank_info|
    rank_info[:submission]
  }.map{|submission, rank_infos|
    rank_infos = rank_infos.map{|rank_info|
      rank_info.select{|k,v| [:benchmark_name, :metric_name, :rank].include?(k) }
    }
    [submission, {ranks: rank_infos}]
  }.to_h
end

def total_rank_for(ranks, submission)
  ranks[submission] && ranks[submission][:total_rank]
end

def rank_for(ranks, submission, benchmark_name, metric_name)
  ranks[submission][:ranks].detect{|info|
    info[:benchmark_name] == benchmark_name && info[:metric_name] == metric_name
  }[:rank]
end

def with_total_ranks(ranked_submissions, use_group_size: false)
  rank_by(ranked_submissions, greater_is_better: false, use_group_size: use_group_size){|submission, rank_infos|
    ranks = rank_infos[:ranks].map{|rank_info| rank_info[:rank] }.compact
    ranks.empty? ? Float::INFINITY : ranks.sum(0.0) / ranks.length
  }.map{|total_rank_info|
    submission, rank_infos = total_rank_info[:object]
    [submission, {ranks: rank_infos[:ranks], total_rank: total_rank_info[:rank]}]
  }.to_h
end

# def best_ranked(submissions)
#   assign_ranks
# end
