ARG RUBY_IMAGE=ruby:3.4.1-alpine

FROM ${RUBY_IMAGE} AS base

RUN addgroup -g 1000 meta \
  && adduser -u 1000 -G meta -D -h /meta meta

WORKDIR /meta

FROM base AS builder

# Install build dependencies
RUN apk add --no-cache git openssl-dev build-base

# Copy all the project files
USER meta

COPY --chown=meta:meta Gemfile Gemfile.lock /meta/
COPY --chown=meta:meta vendor/ /meta/vendor/

# Install project dependencies and build native extensions in deployment mode
# such that we only need the runtime libraries in the runtime container.
RUN bundle config set --local deployment 'true' \
  && bundle config set --local without 'development' \
  && bundle install -j$(nproc)

# Create the runtime image
FROM base

# Install runtime dependencies
RUN apk add --no-cache openssl ffmpeg curl python3 py3-pip git

USER meta

# Install yt-dlp
RUN python3 -m pip install --break-system-packages -U --pre "yt-dlp[default]"

# Copy all the project files.
COPY --chown=meta:meta . /meta
COPY --chown=meta:meta --from=builder /meta/vendor/bundle/ /meta/vendor/bundle/

RUN bundle config set --local deployment 'true' \
  && bundle config set --local without 'development' \
  && bundle install

ENTRYPOINT ["bundle", "exec", "blur", "-l", "trace"]
