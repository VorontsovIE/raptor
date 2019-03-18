SUBMISSION_TYPES = ['motif', 'predictions']

BENCHMARKS = [
  {
    name: 'motif_pseudo_roc',
    submission_type: 'motif',
    docker_image: 'vorontsovie/motif_pseudo_roc',
    metrics: {
      "roc_auc" => {greater_is_better: true},
      "logroc_auc" => {greater_is_better: true},
    },
  },
  {
    name: 'predictions_roc',
    submission_type: 'predictions',
    docker_image: 'vorontsovie/predictions_roc',
    metrics: {
      "roc_auc" => {greater_is_better: true},
    },
  },
]

# METRICS = BENCHMARKS.flat_map{|benchmark_cfg|
#   benchmark_cfg[:metrics].map{|metric_name, metric_cfg|
#     metric_cfg.merge({
#       benchmark_name: benchmark_cfg[:name],
#       metric_name: metric_name,
#     })
#   }
# }

SPECIES_NAME = {
  'human' => 'Homo sapiens',
  'mouse' => 'Mus musculus',
}

# submission variant key should be valid when used as filename
SUBMISSION_VARIANTS = {
  'motif-human-KLF4' => {submission_type: 'motif', species: 'human', tf: 'KLF4', name: 'KLF4 (gut-enriched Krüppel-like factor)'},
  'motif-human-CTCF' => {submission_type: 'motif', species: 'human', tf: 'CTCF', name: 'CTCF'},
  'motif-human-JUN' =>  {submission_type: 'motif', species: 'human', tf: 'JUN', name: 'JUN'},
  'motif-mouse-CTCF' => {submission_type: 'motif', species: 'mouse', tf: 'CTCF', name: 'CTCF'},
  'motif-mouse-JUN' => {submission_type: 'motif', species: 'mouse', tf: 'JUN', name: 'JUN'},
  'motif-mouse-BMAL1' => {submission_type: 'motif', species: 'mouse', tf: 'BMAL1', name: 'BMAL1'},
  'predictions-human-KLF4' => {submission_type: 'predictions', species: 'human', tf: 'KLF4', name: 'KLF4 (gut-enriched Krüppel-like factor)'},
  'predictions-human-JUN' => {submission_type: 'predictions', species: 'human', tf: 'JUN', name: 'JUN'},
}

def benchmarks_by_type(submission_type)
  BENCHMARKS.select{|benchmark|
    benchmark[:submission_type] == submission_type
  }
end

def submission_variants_by_type(submission_type)
  SUBMISSION_VARIANTS.select{|id, variant|
    variant[:submission_type] == submission_type
  }
end

def benchmark_by_name(bm_name)
  BENCHMARKS.detect{|bm| bm[:name] == bm_name }
end
