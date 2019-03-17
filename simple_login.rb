require 'omniauth'

module OmniAuth
  module Strategies
    class SimpleLogin
      include OmniAuth::Strategy

      option :fields, [:email, :name, :password]
      option :uid_field, :email

      uid do
        request.params[options.uid_field.to_s]
      end

      info do
        options.fields.inject({}) do |hash, field|
          hash[field] = request.params[field.to_s]
          hash
        end
      end

      # # def request_phase
      # #   render :login_form
      # # end

      # # def callback_phase
      # #   return fail!(:invalid_credentials) unless identity
      # #   super
      # # end

      # def registration_phase
      #   attributes = (options[:fields] + [:password, :password_confirmation]).inject({}){|h,k| h[k] = request[k.to_s]; h}
      #   @identity = model.create(attributes)
      #   if @identity.persisted?
      #     env['PATH_INFO'] = callback_path
      #     callback_phase
      #   else
      #     if options[:on_failed_registration]
      #       self.env['omniauth.identity'] = @identity
      #       options[:on_failed_registration].call(self.env)
      #     else
      #       registration_form
      #     end
      #   end
      # end

      # def request_phase
      #   form = OmniAuth::Form.new(:title => "User Info", :url => callback_path)
      #   options.fields.each do |field|
      #     form.text_field field.to_s.capitalize.gsub("_", " "), field.to_s
      #   end
      #   form.button "Sign In"
      #   form.to_response
      # end

      # def callback_phase
      #   return fail!(:invalid_credentials) unless identity
      #   super
      # end


      # def other_phase
      #   if on_registration_path?
      #     if request.get?
      #       registration_form
      #     elsif request.post?
      #       registration_phase
      #     end
      #   else
      #     call_app!
      #   end
      # end

###################################################

      # args [:authentication_url]

      # def request_phase
      #   response = Rack::Response.new
      #   response.redirect "#{options.authentication_url}?redir=#{full_host + script_name + callback_path}"
      #   response.finish
      # end

      # def callback_phase
      #   request = Rack::Request.new env
      #   cookies = request.cookies
      #   response = Rack::Response.new

      #   if cookies['honey_badger'] != nil
      #     # code to set a devise/warden or some other local login session
      #     response.redirect some_application_url
      #     response.finish
      #   else
      #     response.status = 401
      #     response.finish
      #   end
      # end

    end
  end
end
