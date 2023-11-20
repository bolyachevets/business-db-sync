FROM registry.redhat.io/rhel9/postgresql-15

USER root
RUN mkdir /opt/app-root && chmod 755 /opt/app-root
WORKDIR /opt/app-root
ENV TZ=PST8PDT
COPY . .
ARG SOURCE_REPO=webdevops
ARG GOCROND_VERSION=23.2.0
ADD https://github.com/$SOURCE_REPO/go-crond/releases/download/$GOCROND_VERSION/go-crond.linux.amd64 /usr/bin/go-crond
#USER root
RUN chmod +x /usr/bin/go-crond
RUN echo $TZ > /etc/timezone
USER 26
ENTRYPOINT ["go-crond", "crontab", "--allow-unprivileged", "--verbose", "--log.json"]
