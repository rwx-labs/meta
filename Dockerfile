FROM ruby:3.3.0-slim-bookworm AS builder

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
FROM ruby:3.3.0-slim-bookworm

# Install runtime dependencies
RUN apt-get update \
  && apt-get install -y exiv2 exiftran libpcap0.8 libssl3 libsqlite3-0 ffmpeg curl python3 \
  && rm -rf /var/lib/apt/lists/*

# Install yt-dlp
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp \
  && chmod a+x /usr/local/bin/yt-dlp

# Install the latest bundler version
RUN gem install bundler

# Copy all the project files.
COPY . /meta
COPY --from=builder /meta/vendor/ /meta/vendor/

# Drop down to a lesser privileged user.
RUN useradd -d /meta meta
RUN chown -R meta:meta /meta

WORKDIR /meta

RUN bundle config set deployment 'true' \
  && bundle config set without 'development' \
  && bundle install

# Expose the RCON port
EXPOSE 31337/tcp

LABEL org.opencontainers.image.authors="Mikkel Kroman <mk@maero.dk>"

ENTRYPOINT ["bundle", "exec", "blur", "-l", "trace"]
