if defined?(ActiveRecord::Base)
  module AttrEncryptor
    module Adapters
      module ActiveRecord
        def self.extended(base) # :nodoc:
          base.class_eval do
            class << self
              alias_method_chain :attr_encrypted, :defined_attributes
              alias_method_chain :attr_encryptor, :defined_attributes
              alias_method_chain :method_missing, :attr_encryptor
              alias_method_chain :where, :attr_encryptor
            end

            attr_encrypted_options[:encode] = true
          end
        end

        protected

        # Ensures the attribute methods for db fields have been defined before calling the original
        # <tt>attr_encrypted</tt> method
        def attr_encrypted_with_defined_attributes(*attrs)
          define_attribute_methods rescue nil
          attr_encrypted_without_defined_attributes *attrs
          attrs.reject { |attr| attr.is_a?(Hash) }.each { |attr| alias_method "#{attr}_before_type_cast", attr }
          encrypted_attributes.each do |attr, args|
            encrypted_attr = args[:attribute]
            define_method("#{attr}_changed?") { send("#{encrypted_attr}_changed?") }
            define_method("#{attr}_was") do
              changed = send("#{encrypted_attr}_change")
              decrypt(attr, changed.first)
            end
            define_method("#{attr}_change") do
              changed = send("#{encrypted_attr}_change")
              [decrypt(attr, changed.first), decrypt(attr, changed.last)]
            end
          end
        end

        alias attr_encryptor_with_defined_attributes attr_encrypted_with_defined_attributes

        # Allows you to use dynamic methods like <tt>find_by_email</tt> or <tt>scoped_by_email</tt> for
        # encrypted attributes
        #
        # This is useful for encrypting fields like email addresses. Your user's email addresses
        # are encrypted in the database, but you can still look up a user by email for logging in
        #
        # Example
        #
        #   class User < ActiveRecord::Base
        #     attr_encrypted :email, :key => 'secret key'
        #   end
        #
        #   User.find_by_email_and_password('test@example.com', 'testing')
        #   # results in a call to
        #   User.find_by_encrypted_email_and_password('the_encrypted_version_of_test@example.com', 'testing')
        def method_missing_with_attr_encryptor(method, *args, &block)
          if match = /^(find|scoped)_(all_by|by)_([_a-zA-Z]\w*)$/.match(method.to_s)
            attribute_names = match.captures.last.split('_and_')
            attribute_names.each_with_index do |attribute, index|
              if attr_encrypted?(attribute)
                args[index] = send("encrypt_#{attribute}", args[index])
                attribute_names[index] = encrypted_attributes[attribute.to_sym][:attribute]
              end
            end
            method = "#{match.captures[0]}_#{match.captures[1]}_#{attribute_names.join('_and_')}".to_sym
          end
          method_missing_without_attr_encryptor(method, *args, &block)
        end

        def where_with_attr_encryptor(opts, *rest)
          if opts.is_a?(Hash)
            opts = opts.map do |attribute, value|
              if attr_encrypted?(attribute)
                new_value = send("encrypt_#{attribute}", value)
                [encrypted_attributes[attribute.to_sym][:attribute], new_value]
              else
                [attribute, value]
              end
            end

            opts = Hash[*opts.flatten]
          end
          where_without_attr_encryptor(opts, *rest)
        end
      end
    end
  end

  ActiveRecord::Base.extend AttrEncryptor::Adapters::ActiveRecord
end
