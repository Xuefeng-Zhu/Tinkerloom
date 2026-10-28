# Build from the project root with:
# docker build -f appnest_server/Dockerfile .
# Local secrets/databases are excluded by .dockerignore. Supply secrets at runtime.

# Build stage
FROM dart:3.13.0 AS build

# Create a minimal workspace that preserves locked server dependency versions.
WORKDIR /app
COPY pubspec.lock .
COPY appnest_server appnest_server
COPY packages/appnest_spec packages/appnest_spec
RUN printf '%s\n' \
  'name: _' \
  'environment:' \
  '  sdk: ">=3.13.0 <3.14.0"' \
  'workspace:' \
  '  - appnest_server' \
  '  - packages/appnest_spec' \
  > pubspec.yaml
RUN dart pub get

# Compile the server executable.
WORKDIR /app/appnest_server
RUN dart build cli --target bin/main.dart --output build
RUN mv build/bundle/bin/main build/bundle/bin/server

# Add a fallback for the copy of possibly missing directories.
RUN mkdir -p config web migrations

# Final stage
FROM alpine:latest
WORKDIR /app

# Environment variables
ENV runmode=production
ENV serverid=default
ENV logging=normal
ENV role=monolith

# Copy runtime dependencies
COPY --from=build /runtime/ /

# Copy compiled server executable and native libraries
COPY --from=build /app/appnest_server/build/bundle/ ./

# Copy configuration files and resources
COPY --from=build /app/appnest_server/config/ config/
COPY --from=build /app/appnest_server/web/ web/
COPY --from=build /app/appnest_server/migrations/ migrations/

# This file is required to enable the endpoint log filter in Insights.
COPY --from=build /app/appnest_server/lib/src/generated/protocol.yaml lib/src/generated/protocol.yaml

# Expose ports
EXPOSE 8080
EXPOSE 8081
EXPOSE 8082

# Define the entrypoint command
ENTRYPOINT ./bin/server --mode=$runmode --server-id=$serverid --logging=$logging --role=$role
