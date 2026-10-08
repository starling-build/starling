FROM swift:6.2-jammy AS build
WORKDIR /src
COPY Package.swift Package.resolved ./
RUN swift package resolve
COPY Sources Sources
RUN swift build -c release --product starling-documents

FROM swift:6.2-jammy-slim
WORKDIR /app
COPY --from=build /src/.build/release/starling-documents /app/
COPY --from=build /src/.build/release/StarlingDocumentService_DocumentService.resources /app/StarlingDocumentService_DocumentService.resources
RUN useradd --system --uid 10001 starling && mkdir -p /data/blobs && chown -R starling /data
USER starling
ENV STARLING_HOST=0.0.0.0 STARLING_STORAGE_PATH=/data/blobs PORT=8090
EXPOSE 8090
ENTRYPOINT ["/app/starling-documents"]
