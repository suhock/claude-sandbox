FROM ubuntu:24.04

RUN apt-get update && apt-get install -y squid dnsmasq dos2unix netcat-openbsd && apt-get clean

COPY squid.conf /etc/squid/squid.conf
COPY dnsmasq.conf /etc/dnsmasq.conf
COPY start.sh /start.sh
RUN dos2unix /start.sh && chmod +x /start.sh

EXPOSE 3128 53/udp

CMD ["/start.sh"]
