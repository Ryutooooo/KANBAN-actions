FROM alpine:3.10

RUN apk add --no-cache --no-progress curl jq

COPY entrypoint.sh /entrypoint.sh
COPY event.json /event.json

ENTRYPOINT ["/entrypoint.sh"]
