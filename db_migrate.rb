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
    String :ticket, null: false, unique: true
    String :name, null: false
    String :submission_variant, null: false
    String :config_hash, null: false
    foreign_key :user_id, :users, null: false
    DateTime :creation_time
    DateTime :submission_time
  end
end

unless DB.table_exists?(:benchmark_runs)
  DB.create_table :benchmark_runs do
    primary_key :id
    foreign_key :submission_id, :submissions, null: false
    String :benchmark_name, null: false
    String :status, null: false
    DateTime :creation_time
    DateTime :modification_time
  end
end

unless DB.table_exists?(:scores)
  DB.create_table :scores do
    primary_key :id
    foreign_key :benchmark_run_id, :benchmark_runs, null: false
    String :metric_name, null: false
    Float :value
    DateTime :creation_time
  end
end
