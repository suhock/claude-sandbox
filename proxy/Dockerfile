FROM alpine:3.21

RUN apk add --no-cache dnsmasq socat iptables ipset

COPY proxy/dnsmasq.conf /etc/dnsmasq.conf
RUN mkdir -p /etc/proxy/allowed-domains.d
COPY proxy/allowed-domains.conf /etc/proxy/allowed-domains.d/00-base.conf
COPY environments/ /etc/proxy/environments/
COPY proxy/start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 22

CMD ["/start.sh"]
