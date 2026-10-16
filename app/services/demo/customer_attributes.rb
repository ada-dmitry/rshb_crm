module Demo
  class CustomerAttributes
    SEED = 20261013

    def self.call(number:)
      previous_locale = Faker::Config.own_locale
      previous_random = Faker::Config.random
      Faker::Config.locale = :ru
      Faker::Config.random = Random.new(SEED + number)

      name = Faker::Name.name
      username = Faker::Base.with_locale(:en) { Faker::Internet.username }
      phone = if number % 9 == 0
        nil
      elsif number % 11 == 0
        "invalid-phone-#{number}"
      else
        format("+79%09d", Faker::Config.random.rand(1_000_000_000))
      end

      {
        name: name,
        email: number % 7 == 0 ? nil : "#{username}.#{number}@example.com",
        phone: phone
      }
    ensure
      Faker::Config.locale = previous_locale
      Faker::Config.random = previous_random
    end
  end
end
