#
FROM docker.io/centos:7
USER root
RUN echo nameserver 10.96.0.10 > /etc/resolv.conf
RUN echo nameserver 8.8.8.8 > /etc/resolv.conf
RUN echo options ndots:2 > /etc/resolv.conf
RUN /usr/bin/yum update -y
RUN /usr/bin/yum install wget git bind-utils net-tools pcre-devel openssl-devel libxml2-devel libxslt-devel gd-devel perl-ExtUtils-Embed GeoIP* -y; yum clean all
RUN /usr/bin/git clone https://github.com/smileserv/pod /smileserv
RUN /bin/mv /smileserv/nginx-cache /usr/local/nginx
RUN /bin/mv /smileserv/perl5 /usr/local/lib64/perl5
RUN /bin/rm -rf /smileserv/nginx-auth
RUN /bin/echo "daemon off;" >> /usr/local/nginx/conf/nginx.conf
RUN /bin/echo "short_open_tag = On" >> /etc/php.ini
RUN /usr/bin/touch /usr/share/empty/index.html
RUN /usr/sbin/adduser nginx -s /sbin/nologin
RUN /usr/bin/mkdir -p /var/log/nginx

EXPOSE 80 443
CMD ["/usr/local/nginx/sbin/nginx"]
