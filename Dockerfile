FROM ruby:2.7.5-slim-buster AS builder

# Install build dependencies
RUN apt-get update && \
  apt-get install -y build-essential git-core libpcap-dev libssl-dev libsqlite3-dev

# Copy all the project files
RUN mkdir -p /meta
WORKDIR /meta

COPY Gemfile Gemfile.lock /meta/
COPY vendor/ /meta/vendor/

# Install project dependencies and build native extensions in deployment mode
# such that we only need the runtime libraries in the runtime container.
RUN gem update bundler \
  && bundle config set deployment 'true' \
  && bundle config set without 'development' \
  && bundle install -j$(nproc)

# Create the runtime image
FROM ruby:2.7.5-slim-buster

# Install runtime dependencies
RUN apt-get update \
  && apt-get install -y exiv2 exiftran libpcap0.8 libssl1.1 libsqlite3-0 ffmpeg curl python3 \
  && rm -rf /var/lib/apt/lists/*

# Install yt-dlp
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp \
  && chmod a+x /usr/local/bin/yt-dlp

# Copy all the project files.
COPY . /meta
COPY --from=builder /meta/vendor/ /meta/vendor/
WORKDIR /meta

RUN bundle config set deployment 'true' \
  && bundle config set without 'development' \
  && bundle install -j$(nproc)

# Expose the RCON port
EXPOSE 31337/tcp

ENTRYPOINT ["bundle", "exec", "blur", "-rblur-url_handling", "-rblur-text_helper"]
