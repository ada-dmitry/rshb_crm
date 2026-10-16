require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module RshbStipa
  class Application < Rails::Application
    config.load_defaults 8.1
    # Preserve PostgreSQL trigger invariants in test/parallel/fresh databases.
    config.active_record.schema_format = :sql

    config.autoload_lib(ignore: %w[assets tasks])
  end
end
