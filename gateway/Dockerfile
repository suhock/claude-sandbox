FROM alpine:3.21

RUN apk add --no-cache dnsmasq socat iptables ipset

COPY gateway/dnsmasq.conf /etc/dnsmasq.conf
RUN mkdir -p /etc/gateway/allowed-domains.d
COPY gateway/allowed-domains.conf /etc/gateway/allowed-domains.d/00-base.conf
COPY environments/ /etc/gateway/environments/
COPY gateway/start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 22

CMD ["/start.sh"]
