#
FROM docker.io/centos:7
USER root
RUN echo nameserver 10.96.0.10 > /etc/resolv.conf
RUN echo nameserver 8.8.8.8 > /etc/resolv.conf
RUN echo options ndots:2 > /etc/resolv.conf
RUN /usr/bin/yum update -y
RUN /usr/bin/yum install wget git bind-utils net-tools -y; yum clean all
RUN /usr/bin/git clone https://github.com/smileserv/pod /smileserv
RUN /bin/mv /smileserv/nginx-auth7 /usr/local/nginx
RUN /bin/echo "daemon off;" >> /usr/local/nginx/conf/nginx.conf
RUN /bin/echo "short_open_tag = On" >> /etc/php.ini

EXPOSE 80 443 1935
CMD ["/usr/local/nginx/sbin/nginx"]
