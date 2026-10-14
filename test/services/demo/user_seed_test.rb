require "test_helper"

class DemoUserSeedTest < ActiveSupport::TestCase
  test "creates a normalized demo user with a hashed password" do
    assert_difference "User.count", 1 do
      assert_equal :created, Demo::UserSeed.call(email: " FARMER@EXAMPLE.COM ", password: "demo-test-password")
    end
    user = User.find_by!(email_address: "farmer@example.com")
    assert user.authenticate("demo-test-password")
    assert_not_equal "demo-test-password", user.password_digest
  end

  test "repeated preparation preserves credentials and sessions" do
    user = users(:one)
    session = user.sessions.create!
    assert_no_difference [ "User.count", "Session.count" ] do
      assert_equal :existing, Demo::UserSeed.call(email: " ONE@EXAMPLE.COM ", password: "a-different-password")
    end
    assert user.reload.authenticate("password")
    assert Session.exists?(session.id)
  end

  test "requires a valid email and a password of 12 to 72 bytes for a new user" do
    [ nil, "", "not-an-email" ].each do |email|
      assert_raises(ArgumentError) { Demo::UserSeed.call(email: email, password: "demo-test-password") }
    end
    [ nil, "", "short", " " * 12, "x" * 73, "я" * 37 ].each do |password|
      assert_no_difference "User.count" do
        assert_raises(ArgumentError) { Demo::UserSeed.call(email: "new@example.com", password: password) }
      end
    end
  end

  test "refuses to prepare a demo user in production" do
    original_env = Rails.env
    Rails.env = "production"
    assert_no_difference "User.count" do
      assert_raises(ArgumentError) { Demo::UserSeed.call(email: "new@example.com", password: "demo-test-password") }
    end
  ensure
    Rails.env = original_env
  end

  test "seeds without explicit credentials do not create users" do
    original_email = ENV.delete("DEMO_EMAIL")
    original_password = ENV.delete("DEMO_PASSWORD")
    assert_no_difference "User.count" do
      load Rails.root.join("db/seeds.rb")
    end
  ensure
    ENV["DEMO_EMAIL"] = original_email
    ENV["DEMO_PASSWORD"] = original_password
  end
end
