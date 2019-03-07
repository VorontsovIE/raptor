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

SUBMISSION_VARIANTS = {
  'human:KLF4:motif' => {submission_type: 'motif', species: "human", tf: "KLF4", name: "KLF4 (gut-enriched Krüppel-like factor); Homo sapiens"},
  'human:KLF4:predictions' => {submission_type: 'predictions', species: "human", tf: "KLF4", name: "KLF4 (gut-enriched Krüppel-like factor); Homo sapiens"},
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
