class TokenGenerator
  def self.call
    SecureRandom.urlsafe_base64(32)
  end
end
