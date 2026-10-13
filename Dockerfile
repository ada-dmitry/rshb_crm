FROM docker.io/library/ruby:4.0.7-slim

# Development/demo image: includes the test gems for Compose verification.
WORKDIR /rails
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config curl && \
    rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=development \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_FROZEN=true

COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v 4.0.20 --no-document && bundle install
COPY . .

RUN groupadd --gid 1000 rails && \
    useradd --uid 1000 --gid 1000 --create-home rails && \
    mkdir -p tmp/pids log storage && chown -R rails:rails /rails
USER rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
