require 'sequel'

module OmniAuth
  module Identity
    module Models
      module Sequel
        def self.included(base)
          base.class_eval do
            include ::OmniAuth::Identity::Model
            include ::OmniAuth::Identity::SecurePassword
            plugin :validation_class_methods
            plugin :active_model

            has_secure_password
            attr_accessor :password_confirmation

            def self.auth_key=(key)
              super
              validates_uniqueness_of key, :case_sensitive => false
            end

            def self.locate(search_hash)
              conditions = search_hash.map{|k,v|
                [k.to_sym, v]
              }
              first(conditions)
            end
          end
        end
      end
    end
  end
end
