FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata wget && \
    addgroup -S appgroup && adduser -S appuser -G appgroup -h /home/appuser && \
    mkdir -p /etc/oc-go-cc /home/appuser/.config/oc-go-cc && \
    chown -R appuser:appgroup /etc/oc-go-cc /home/appuser/.config

COPY oc-go-cc_linux-amd64 /usr/local/bin/oc-go-cc
COPY config.json /etc/oc-go-cc/config.json
RUN chmod +x /usr/local/bin/oc-go-cc && \
    chown appuser:appgroup /usr/local/bin/oc-go-cc /etc/oc-go-cc/config.json

USER appuser

ENV OC_GO_CC_CONFIG=/etc/oc-go-cc/config.json
ENV OC_GO_CC_HOST=0.0.0.0

EXPOSE 3456

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:3456/health || exit 1

ENTRYPOINT ["oc-go-cc", "serve"]