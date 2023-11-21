FROM registry.redhat.io/rhel9/postgresql-15
USER root
RUN mkdir /opt/app-root2 && chmod 755 /opt/app-root2
WORKDIR /opt/app-root2
ENV TZ=PST8PDT
COPY . .
ARG SOURCE_REPO=webdevops
ARG GOCROND_VERSION=23.2.0
ADD https://github.com/$SOURCE_REPO/go-crond/releases/download/$GOCROND_VERSION/go-crond.linux.amd64 /usr/bin/go-crond
RUN chmod +x /usr/bin/go-crond
RUN chmod +x /opt/app-root2/run.sh
RUN echo $TZ > /etc/timezone
ENTRYPOINT ["go-crond", "crontab", "--allow-unprivileged", "--verbose", "--log.json"]
