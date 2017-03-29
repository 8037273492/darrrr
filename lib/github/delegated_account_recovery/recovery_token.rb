# frozen_string_literal: true

# Handles binary serialization/deserialization of recovery token data. It does
# not manage signing/verification of tokens.

module GitHub
  module DelegatedAccountRecovery
    class RecoveryToken
      extend Forwardable

      attr_reader :token_object

      def_delegators :@token_object, :token_id, :issuer, :issued_time, :options,
        :audience, :binding_data, :data, :version, :to_binary_s, :num_bytes, :data=, :token_type=, :token_type

      BASE64_CHARACTERS = /\A[0-9a-zA-Z+\/=]+\z/

      # Typically, you would not call `new` directly but instead use `build`
      # and `parse`
      #
      # token_object: a RecoveryTokenWriter/RecoveryTokenReader instance
      def initialize(token_object)
        @token_object = token_object
      end
      private_class_method :new

      def decode
        EncryptedData.parse(self.data.to_binary_s).decrypt
      end

      # A globally known location of the token, used to initiate a recovery
      def state_url
        [DelegatedAccountRecovery.recovery_provider(self.audience).recover_account, "id=#{CGI::escape(token_id.to_hex)}"].join("?")
      end

      class << self
        # data: the value that will be encrypted by EncryptedData.
        # recovery_provider: the provider for which we are building the token.
        # binding_data: a value retrieved from the recovery provider for this
        # token.
        #
        # returns a RecoveryToken.
        def build(issuer:, audience:, type:)
          token = RecoveryTokenWriter.new.tap do |token|
            token.token_id = SecureRandom.random_bytes(16).bytes.to_a
            token.issuer = issuer.origin
            token.issued_time = Time.now.utc.iso8601
            token.options = 0 # when the token-status endpoint is implemented, change this to 1
            token.audience = audience.origin
            token.version = DelegatedAccountRecovery::PROTOCOL_VERSION
            token.token_type = type
          end
          new(token)
        end

        # serialized_data: a binary string representation of a RecoveryToken.
        #
        # returns a RecoveryToken.
        def parse(serialized_data)
          new RecoveryTokenReader.new.read(serialized_data)
        rescue IOError => e
          message = e.message
          if serialized_data =~ BASE64_CHARACTERS
            message = "#{message}: did you forget to Base64.strict_decode64 this value?"
          end
          raise RecoveryTokenSerializationError, message
        end

        # Extract a recovery provider from a token based on the token type.
        #
        # serialized_data: a binary string representation of a RecoveryToken.
        #
        # returns the recovery provider for the coutnersigned token or raises an
        #   error if the token is a recovery token
        def recovery_provider_issuer(serialized_data)
          issuer(serialized_data, DelegatedAccountRecovery::COUNTERSIGNED_RECOVERY_TOKEN_TYPE)
        end

        # Extract an account provider from a token based on the token type.
        #
        # serialized_data: a binary string representation of a RecoveryToken.
        #
        # returns the account provider for the recovery token or raises an error
        #   if the token is a countersigned token
        def account_provider_issuer(serialized_data)
          issuer(serialized_data, DelegatedAccountRecovery::RECOVERY_TOKEN_TYPE)
        end

        # Convenience method to find the issuer of the token
        #
        # serialized_data: a binary string representation of a RecoveryToken.
        #
        # raises an error if the token is the not the expected type
        # returns the account provider or recovery provider instance based on the
        #   token type
        private def issuer(serialized_data, token_type)
          parsed_token = parse(serialized_data)
          raise TokenFormatError, "Token type must be #{token_type}" unless parsed_token.token_type == token_type

          issuer = parsed_token.issuer
          case token_type
          when DelegatedAccountRecovery::RECOVERY_TOKEN_TYPE
            DelegatedAccountRecovery.account_provider(issuer)
          when DelegatedAccountRecovery::COUNTERSIGNED_RECOVERY_TOKEN_TYPE
            DelegatedAccountRecovery.recovery_provider(issuer)
          else
            raise RecoveryTokenError, "Could not determine provider"
          end
        end
      end
    end
  end
end
