require "test_helper"

class DemoCustomerAttributesTest < ActiveSupport::TestCase
  setup { assert Demo.const_defined?(:CustomerAttributes), "Demo::CustomerAttributes is not implemented" }

  test "repeats contacts independently of call order and external randomness" do
    original = (1..200).to_h { |number| [ number, Demo::CustomerAttributes.call(number: number) ] }
    Faker::Name.name
    original.keys.reverse_each do |number|
      assert_equal original.fetch(number), Demo::CustomerAttributes.call(number: number)
    end
  end

  test "generates varied Russian names unique ASCII emails and Russian phones with edge cases" do
    contacts = (1..200).map { |number| Demo::CustomerAttributes.call(number: number) }
    assert_operator contacts.pluck(:name).uniq.length, :>, 100
    emails = contacts.pluck(:email).compact
    assert_equal emails.length, emails.uniq.length

    contacts.each.with_index(1) do |attributes, number|
      assert_match(/[А-Яа-яЁё]/, attributes.fetch(:name))
      if number % 7 == 0
        assert_nil attributes.fetch(:email)
      else
        assert_match(/\A[a-z0-9._-]+#{number}@example\.com\z/, attributes.fetch(:email))
      end
      if number % 9 == 0
        assert_nil attributes.fetch(:phone)
      elsif number % 11 == 0
        assert_no_match(/\A\+7\d{10}\z/, attributes.fetch(:phone))
        assert attributes.fetch(:phone).present?
      else
        assert_match(/\A\+7\d{10}\z/, attributes.fetch(:phone))
      end
    end
  end

  test "restores Faker settings and leaves application locale unchanged" do
    with_faker_settings do
      locale = I18n.locale
      random = Faker::Config.random
      Demo::CustomerAttributes.call(number: 1)
      assert_equal :en, Faker::Config.locale
      assert_same random, Faker::Config.random
      assert_equal Random.new(123).rand, random.rand
      assert_equal locale, I18n.locale
    end
  end

  test "restores Faker settings even when generation raises" do
    with_faker_settings do
      random = Faker::Config.random
      locale = I18n.locale
      original_name = Faker::Name.method(:name)
      Faker::Name.define_singleton_method(:name) do
        raise "Controlled generation failure"
      end
      assert_raises(RuntimeError) { Demo::CustomerAttributes.call(number: 1) }
      assert_equal :en, Faker::Config.locale
      assert_same random, Faker::Config.random
      assert_equal locale, I18n.locale
    ensure
      Faker::Name.define_singleton_method(:name, original_name) if original_name
    end
  end

  private
    def with_faker_settings
      locale = Faker::Config.locale
      random = Faker::Config.random
      Faker::Config.locale = :en
      Faker::Config.random = Random.new(123)
      yield
    ensure
      Faker::Config.locale = locale
      Faker::Config.random = random
    end
end
