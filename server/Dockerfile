# Build from the repository root (the server depends on packages/coup_domain):
#   docker build -f server/Dockerfile .
FROM dart:3.10 AS build
WORKDIR /app

# Resolve dependencies first so this layer is cached between code changes.
COPY packages/coup_domain/pubspec.yaml packages/coup_domain/
COPY server/pubspec.yaml server/pubspec.lock server/
RUN cd server && dart pub get

COPY packages/coup_domain packages/coup_domain
COPY server server
RUN cd server && dart pub get --offline \
    && dart compile exe bin/server.dart -o /app/coup-server

# Minimal image: the compiled server plus the Dart runtime's system libraries.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/coup-server /app/coup-server

# Supabase settings come from the host's secrets, never from a file here.
ENV PORT=8080
EXPOSE 8080
CMD ["/app/coup-server"]
