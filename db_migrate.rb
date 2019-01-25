require 'sequel'
require 'sqlite3'

DB = Sequel.sqlite('db.sqlite')
Sequel::Model.db = DB

unless DB.table_exists?(:users)
  DB.create_table :users do
    primary_key :id
    String :name,  null: false, unique: true
    String :email, null: false, unique: true
    String :password_digest, null: false
  end
end

unless DB.table_exists?(:submissions)
  DB.create_table :submissions do
    primary_key :id
    String :ticket, null: false, unique: true, index: true
    foreign_key :user_id, :users, null: false, index: true
    foreign_key :submission_variant_id, :submission_variants, null: false, index: true
    DateTime :creation_time
  end
end

unless DB.table_exists?(:submission_variants)
  DB.create_table :submission_variants do
    primary_key :id
    String :submission_type, null: false, index: true # motif/predictions (it's also a name for AMQP exchange to send messages)
    String :tf, null: false, index: true # e.g. `P53`
    String :species, null: false, index: true # e.g. `human`
    String :name, null: false, index: true # e.g. `NFKB-α (Homo sapiens)`
  end
end

unless DB.table_exists?(:benchmarks)
  DB.create_table :benchmarks do
    primary_key :id
    String :name, null: false, unique: true, index: true # e.g. `motif.hocomoco` (name should be possible to use as a name for AMQP exchange)
    String :docker_image, null: false
    String :submission_type, null: false, index: true # motif/predictions
  end
end

unless DB.table_exists?(:benchmark_runs)
  DB.create_table :benchmark_runs do
    primary_key :id
    foreign_key :submission_id, :submissions, null: false, index: true
    foreign_key :benchmark_id, :benchmarks, null: false, index: true
    String :status, null: false, index: true
    DateTime :creation_time
    DateTime :modification_time
  end
end

unless DB.table_exists?(:scores)
  DB.create_table :scores do
    primary_key :id
    foreign_key :benchmark_run_id, :benchmark_runs, null: false, index: true
    foreign_key :measure_type_id, :measure_types, null: false, index: true
    Float :value, index: true
    DateTime :creation_time
  end
end

unless DB.table_exists?(:measure_types)
  DB.create_table :measure_types do
    primary_key :id
    foreign_key :benchmark_id, :benchmarks, null: false, index: true
    String :name, null: false, index: true # e.g. `logAUC`
    index [:benchmark_id, :name], unique: true
    TrueClass :greater_is_better, null: false
  end
end
