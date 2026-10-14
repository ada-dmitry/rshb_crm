if ENV.key?("DEMO_EMAIL") || ENV.key?("DEMO_PASSWORD")
  result = Demo::UserSeed.call(email: ENV["DEMO_EMAIL"], password: ENV["DEMO_PASSWORD"])
  puts(result == :created ? "Демопользователь создан." : "Демопользователь уже существует; доступ не изменён.")
end

Demo::UserSeed.call(
  email: "farmer@example.com",
  password: "local-demo-password"
)

Demo::Seed.call
puts "Демоданные подготовлены; существующие записи сохранены."
