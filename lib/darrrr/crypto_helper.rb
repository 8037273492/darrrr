# frozen_string_literal: true

module Darrrr
  module CryptoHelper
    include Constants
    # Signs the provided token and joins the data with the signature.
    #
    # token: a RecoveryToken instance
    #
    # returns a base64 value for the binary token string and the signature
    # of the token.
    def seal(token)
      raise RuntimeError, "signing private key must be set" unless self.signing_private_key
      binary_token = token.to_binary_s
      signature = Darrrr.encryptor.sign(binary_token, self.signing_private_key)
      Base64.strict_encode64([binary_token, signature].join)
    end

    # Splits the payload by the token size, treats the remaining portion as
    # the signature of the payload, and verifies the signature is valid for
    # the given payload.
    #
    # token_and_signature: binary string consisting of [token_binary_str, signature].join
    # keys - An array of public keys to use for signature verification.
    #
    # returns a RecoveryToken if the payload has been verified and
    # deserializes correctly. Raises exceptions if any crypto fails.
    # Raises an error if the token's version field is not valid.
    def unseal(token_and_signature)
      token = RecoveryToken.parse(token_and_signature)

      unless token.version.to_i == PROTOCOL_VERSION
        raise TokenFormatError, "Version field must be #{PROTOCOL_VERSION}"
      end

      token_data, signature = partition_signed_token(token_and_signature, token)
      self.unseal_keys.each do |key|
        return token if Darrrr.encryptor.verify(token_data, signature, key)
      end
      raise CryptoError, "Recovery token signature was invalid"
    end

    # Split the binary token into the token data and the signature over the
    # data.
    #
    # token_and_signature: binary serialization of the token and signature for the token
    # recovery_token: a RecoveryToken object parsed from token_and_signature
    #
    # returns a two element array of [token, signature]
    private def partition_signed_token(token_and_signature, recovery_token)
      token_length = recovery_token.num_bytes
      [token_and_signature[0...token_length], token_and_signature[token_length..-1]]
    end
  end
end
