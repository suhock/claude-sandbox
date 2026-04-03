FROM alpine:3.21

RUN apk add --no-cache squid dnsmasq

COPY squid.conf /etc/squid/squid.conf
COPY dnsmasq.conf /etc/dnsmasq.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 3128 53/udp

CMD ["/start.sh"]
