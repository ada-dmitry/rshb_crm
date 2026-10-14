module Demo
  class UserSeed
    def self.call(email:, password:)
      unless Rails.env.development? || Rails.env.test?
        raise ArgumentError, "Демопользователь разрешён только в development и test."
      end

      email = email.to_s.strip.downcase
      unless URI::MailTo::EMAIL_REGEXP.match?(email)
        raise ArgumentError, "Задайте корректный DEMO_EMAIL."
      end
      return :existing if User.exists?(email_address: email)

      unless password.present? && password.bytesize.between?(12, 72)
        raise ArgumentError, "DEMO_PASSWORD должен содержать от 12 до 72 байт и не состоять из пробелов."
      end

      User.create!(email_address: email, password: password)
      :created
    end
  end
end
